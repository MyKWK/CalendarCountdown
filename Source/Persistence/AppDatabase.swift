#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import Foundation
import SQLite3

public struct AppDatabase: Sendable {
    public let path: String
    public let deviceID: UUID
    let connection: SQLiteDatabase

    public static func open(
        at url: URL,
        backupDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> AppDatabase {
        try AppDatabasePoolRegistry.shared.intern(path: url.standardizedFileURL.path) {
            try openUncached(at: url, backupDirectory: backupDirectory, fileManager: fileManager)
        }
    }

    public static func openSharedContainer(fileManager: FileManager = .default) throws -> AppDatabase {
        let database = try open(
            at: try SharedContainer.sqliteDatabaseURL(fileManager: fileManager),
            backupDirectory: try SharedContainer.sqliteBackupDirectoryURL(fileManager: fileManager),
            fileManager: fileManager
        )
        try CountdownStore(db: database).importLegacyJSONIfNeeded(fileManager: fileManager)
        return database
    }

    public static func openTemporary(fileManager: FileManager = .default) throws -> AppDatabase {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("cc-db-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try open(
            at: directory.appendingPathComponent("calendarcountdown-v2.sqlite"),
            backupDirectory: directory.appendingPathComponent("Backups", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func write<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        try connection.transaction(body)
    }

    public func read<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        try connection.read(body)
    }

    public func close() throws {
        AppDatabasePoolRegistry.shared.remove(path: path)
        try connection.close()
    }

    public func lastFetchAt() throws -> Date? {
        try read { db in
            RFC3339.parse(try db.string("SELECT value FROM local_kv WHERE key = ?", ["last_fetch_at"]))
        }
    }

    public func recordFetchOutcome(_ outcome: CloudFetchOutcome, now: Date = Date()) throws {
        guard outcome != .failed else { return }
        try write { db in
            try db.execute(
                "INSERT INTO local_kv(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                ["last_fetch_at", RFC3339.utcString(from: now)]
            )
        }
    }

    private static func openUncached(
        at url: URL,
        backupDirectory: URL?,
        fileManager: FileManager
    ) throws -> AppDatabase {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SQLiteFilePolicy.protectDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        let connection = try SQLiteDatabase(path: url.path)
        try SQLiteFilePolicy.protectDatabase(at: url, fileManager: fileManager)
        let placeholder = AppDatabase(path: url.path, deviceID: UUID(), connection: connection)
        let backups = try backupDirectory ?? SharedContainer.sqliteBackupDirectoryURL(fileManager: fileManager)
        try SQLiteFilePolicy.protectDirectory(backups, fileManager: fileManager)
        try placeholder.migrate()
        try SQLiteFilePolicy.protectDatabase(at: url, fileManager: fileManager)
        let deviceID = try placeholder.ensureDeviceID()
        return AppDatabase(path: url.path, deviceID: deviceID, connection: connection)
    }

    private func migrate() throws {
        try connection.execute(Self.schemaSQL)
    }

    private func ensureDeviceID() throws -> UUID {
        try write { db in
            if let value = try db.string("SELECT value FROM local_kv WHERE key = ?", ["device_id"]),
               let uuid = UUID(uuidString: value) {
                return uuid
            }
            let uuid = UUID()
            try db.execute(
                "INSERT INTO local_kv(key, value) VALUES(?, ?)",
                ["device_id", uuid.uuidString.lowercased()]
            )
            return uuid
        }
    }

    private static let schemaSQL = """
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;
        PRAGMA busy_timeout = 5000;

        CREATE TABLE IF NOT EXISTS local_kv (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS missions (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revision INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at TEXT
        );

        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            due_date TEXT,
            is_completed INTEGER NOT NULL,
            completed_at TEXT,
            mission_id TEXT,
            workload INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revision INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at TEXT
        );

        CREATE TABLE IF NOT EXISTS habits (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revision INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at TEXT
        );

        CREATE TABLE IF NOT EXISTS checkins (
            id TEXT PRIMARY KEY NOT NULL,
            habit_id TEXT NOT NULL,
            occurred_on TEXT NOT NULL,
            note TEXT NOT NULL,
            created_at TEXT NOT NULL,
            revision INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at TEXT
        );

        CREATE TABLE IF NOT EXISTS managed_events (
            id TEXT PRIMARY KEY NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revision INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at TEXT
        );

        CREATE TABLE IF NOT EXISTS countdown_selections (
            id TEXT PRIMARY KEY NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revision INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at TEXT
        );

        CREATE TABLE IF NOT EXISTS countdown_preferences (
            id TEXT PRIMARY KEY NOT NULL,
            pinned_selection_id TEXT,
            revision INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            modified_by_device TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS countdown_hidden_calendars (
            calendar_identifier TEXT PRIMARY KEY NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cloud_outbox (
            id TEXT PRIMARY KEY NOT NULL,
            record_type TEXT NOT NULL,
            record_name TEXT NOT NULL,
            operation TEXT NOT NULL,
            revision INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            modified_by_device TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cloud_sync_state (
            scope TEXT PRIMARY KEY NOT NULL,
            last_fetch_at TEXT,
            last_send_at TEXT,
            account_hash TEXT
        );
        """
}

public final class SQLiteDatabase: @unchecked Sendable {
    private var pointer: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw DomainStoreError.sqlite("无法打开 SQLite：\(path)")
        }
        pointer = handle
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA busy_timeout = 5000")
        try execute("PRAGMA synchronous = NORMAL")
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        if let pointer {
            sqlite3_close(pointer)
            self.pointer = nil
        }
    }

    func transaction<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try executeUnlocked("BEGIN IMMEDIATE")
        do {
            let value = try body(self)
            try executeUnlocked("COMMIT")
            return value
        } catch {
            try? executeUnlocked("ROLLBACK")
            throw error
        }
    }

    func read<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(self)
    }

    func execute(_ sql: String, _ bindings: [Any?] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        try executeUnlocked(sql, bindings)
    }

    func string(_ sql: String, _ bindings: [Any?] = []) throws -> String? {
        try query(sql, bindings).first.flatMap { $0["value"] ?? $0.values.first }
    }

    func query(_ sql: String, _ bindings: [Any?] = []) throws -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return try queryUnlocked(sql, bindings)
    }

    fileprivate func executeUnlocked(_ sql: String, _ bindings: [Any?] = []) throws {
        let statements = sql.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if statements.count > 1 && bindings.isEmpty {
            for statement in statements {
                try run(statement, [])
            }
            return
        }
        try run(sql, bindings)
    }

    private func queryUnlocked(_ sql: String, _ bindings: [Any?]) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DomainStoreError.sqlite(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, bindings)
        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let text = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: text)
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func run(_ sql: String, _ bindings: [Any?]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DomainStoreError.sqlite(errorMessage + " SQL: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, bindings)
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            throw DomainStoreError.sqlite(errorMessage)
        }
    }

    private func bind(_ statement: OpaquePointer, _ bindings: [Any?]) throws {
        for (index, value) in bindings.enumerated() {
            let slot = Int32(index + 1)
            switch value {
            case nil:
                sqlite3_bind_null(statement, slot)
            case let string as String:
                sqlite3_bind_text(statement, slot, string, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let int as Int:
                sqlite3_bind_int64(statement, slot, Int64(int))
            case let int as Int64:
                sqlite3_bind_int64(statement, slot, int)
            case let bool as Bool:
                sqlite3_bind_int(statement, slot, bool ? 1 : 0)
            case let uuid as UUID:
                sqlite3_bind_text(statement, slot, uuid.uuidString.lowercased(), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            default:
                sqlite3_bind_text(statement, slot, "\(value!)", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
    }

    private var errorMessage: String {
        guard let pointer else { return "SQLite 已关闭" }
        return String(cString: sqlite3_errmsg(pointer))
    }
}

enum SQLiteFilePolicy {
    static func protectDirectory(_ url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try mark(url)
    }

    static func protectDatabase(at url: URL, fileManager: FileManager) throws {
        try mark(url.deletingLastPathComponent())
        let sidecars = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ]
        for file in sidecars where fileManager.fileExists(atPath: file.path) {
            try mark(file)
        }
    }

    private static func mark(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        #if os(iOS)
        values.fileProtection = .completeUntilFirstUserAuthentication
        #endif
        var mutable = url
        try mutable.setResourceValues(values)
    }
}

final class AppDatabasePoolRegistry: @unchecked Sendable {
    static let shared = AppDatabasePoolRegistry()
    private let lock = NSLock()
    private var databases: [String: AppDatabase] = [:]

    func intern(path: String, create: () throws -> AppDatabase) throws -> AppDatabase {
        lock.lock()
        defer { lock.unlock() }
        if let existing = databases[path] {
            return existing
        }
        let opened = try create()
        databases[path] = opened
        return opened
    }

    func remove(path: String) {
        lock.lock()
        databases.removeValue(forKey: path)
        lock.unlock()
    }
}

public struct CountdownStore: Sendable {
    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func importLegacyJSONIfNeeded(fileManager: FileManager = .default) throws {
        let flagURL = try SharedContainer.rootURL(fileManager: fileManager)
            .appendingPathComponent(".countdown-sqlite-imported")
        guard !fileManager.fileExists(atPath: flagURL.path) else { return }
        let events = (try? ManagedEventFileStore.load(fileManager: fileManager)) ?? []
        let selections = (try? CountdownSelectionStore.load(fileManager: fileManager)) ?? []
        let preferences = CountdownDisplayPreferencesStore.load(fileManager: fileManager)
        try db.write { db in
            for record in events {
                try Self.persistManaged(record, db: db)
            }
            for selection in selections {
                try Self.persistSelection(selection, db: db)
            }
        }
        try persistPreferences(preferences)
        try Data().write(to: flagURL, options: .atomic)
    }

    public func persistManaged(_ record: ManagedEventRecord) throws {
        try db.write { db in
            try Self.persistManaged(record, db: db)
            try Self.enqueue(
                db,
                recordType: "CDManagedEvent",
                recordName: record.id,
                operation: record.deletedAt == nil ? "upsert" : "delete",
                revision: record.revision,
                payload: CountdownManagedCloudPayload(record),
                modifiedByDevice: record.modifiedByDevice,
                updatedAt: record.updatedAt
            )
        }
    }

    public func persistSelection(_ selection: CountdownSelection) throws {
        try db.write { db in
            try Self.persistSelection(selection, db: db)
            try Self.enqueue(
                db,
                recordType: "CDCountdownSelection",
                recordName: selection.id,
                operation: selection.deletedAt == nil ? "upsert" : "delete",
                revision: selection.revision,
                payload: CountdownSelectionCloudPayload(selection),
                modifiedByDevice: selection.modifiedByDevice,
                updatedAt: selection.updatedAt
            )
        }
    }

    public func persistPreferences(_ preferences: CountdownDisplayPreferences, now: Date = Date()) throws {
        try db.write { db in
            let id = CloudRecordIdentity.countdownPreferences
            var revision: Int64 = 1
            if let row = try db.query("SELECT revision FROM countdown_preferences WHERE id = ?", [id.uuidString.lowercased()]).first,
               let current = row["revision"].flatMap({ Int64($0) }) {
                revision = current + 1
            }
            try db.execute(
                """
                INSERT INTO countdown_preferences(id, pinned_selection_id, revision, updated_at, modified_by_device)
                VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    pinned_selection_id = excluded.pinned_selection_id,
                    revision = excluded.revision,
                    updated_at = excluded.updated_at,
                    modified_by_device = excluded.modified_by_device
                """,
                [
                    id.uuidString.lowercased(),
                    preferences.pinnedSelectionID?.uuidString.lowercased(),
                    revision,
                    RFC3339.utcString(from: now),
                    dbDevice
                ]
            )
            try db.execute("DELETE FROM countdown_hidden_calendars")
            for identifier in preferences.untrackedCalendarIdentifiers {
                try db.execute(
                    "INSERT INTO countdown_hidden_calendars(calendar_identifier, updated_at) VALUES(?, ?)",
                    [identifier, RFC3339.utcString(from: now)]
                )
            }
            try Self.enqueue(
                db,
                recordType: "CDCountdownPreferences",
                recordName: id,
                operation: "upsert",
                revision: revision,
                payload: CountdownPreferencesCloudPayload(
                    id: id,
                    pinnedSelectionID: preferences.pinnedSelectionID,
                    revision: revision,
                    updatedAt: now,
                    modifiedByDevice: self.db.deviceID
                ),
                modifiedByDevice: self.db.deviceID,
                updatedAt: now
            )
        }
    }

    public func pendingOutbox() throws -> [CloudOutboxItem] {
        try db.read { db in
            try db.query("SELECT * FROM cloud_outbox ORDER BY updated_at ASC").map(Self.outbox(from:))
        }
    }

    private var dbDevice: String { db.deviceID.uuidString.lowercased() }

    private static func persistManaged(_ record: ManagedEventRecord, db: SQLiteDatabase) throws {
        let data = try JSONCoding.encoder(pretty: false).encode(record)
        try db.execute(
            """
            INSERT INTO managed_events(id, payload_json, created_at, updated_at, revision, modified_by_device, deleted_at)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                modified_by_device = excluded.modified_by_device,
                deleted_at = excluded.deleted_at
            """,
            [
                record.id.uuidString.lowercased(),
                String(decoding: data, as: UTF8.self),
                RFC3339.utcString(from: record.createdAt),
                RFC3339.utcString(from: record.updatedAt),
                record.revision,
                record.modifiedByDevice.uuidString.lowercased(),
                record.deletedAt.map(RFC3339.utcString(from:))
            ]
        )
    }

    private static func persistSelection(_ selection: CountdownSelection, db: SQLiteDatabase) throws {
        let data = try JSONCoding.encoder(pretty: false).encode(selection)
        try db.execute(
            """
            INSERT INTO countdown_selections(id, payload_json, updated_at, revision, modified_by_device, deleted_at)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at,
                revision = excluded.revision,
                modified_by_device = excluded.modified_by_device,
                deleted_at = excluded.deleted_at
            """,
            [
                selection.id.uuidString.lowercased(),
                String(decoding: data, as: UTF8.self),
                RFC3339.utcString(from: selection.updatedAt),
                selection.revision,
                selection.modifiedByDevice.uuidString.lowercased(),
                selection.deletedAt.map(RFC3339.utcString(from:))
            ]
        )
    }

    private static func enqueue<T: Encodable>(
        _ db: SQLiteDatabase,
        recordType: String,
        recordName: UUID,
        operation: String,
        revision: Int64,
        payload: T,
        modifiedByDevice: UUID,
        updatedAt: Date
    ) throws {
        let json = String(decoding: try JSONCoding.encoder(pretty: false).encode(payload), as: UTF8.self)
        try db.execute(
            """
            INSERT INTO cloud_outbox(id, record_type, record_name, operation, revision, payload_json, modified_by_device, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                UUID().uuidString.lowercased(),
                recordType,
                recordName.uuidString.lowercased(),
                operation,
                revision,
                json,
                modifiedByDevice.uuidString.lowercased(),
                RFC3339.utcString(from: updatedAt)
            ]
        )
    }

    private static func outbox(from row: [String: String]) -> CloudOutboxItem {
        CloudOutboxItem(
            id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
            recordType: row["record_type"] ?? "",
            recordName: UUID(uuidString: row["record_name"] ?? "") ?? UUID(),
            operation: row["operation"] ?? "upsert",
            revision: Int64(row["revision"] ?? "1") ?? 1,
            payloadJSON: row["payload_json"] ?? "{}",
            modifiedByDevice: UUID(uuidString: row["modified_by_device"] ?? "") ?? UUID(),
            updatedAt: RFC3339.parse(row["updated_at"]) ?? Date()
        )
    }
}

private extension SQLiteDatabase {
    var deviceID: UUID {
        UUID(uuidString: (try? string("SELECT value FROM local_kv WHERE key = ?", ["device_id"])) ?? "") ?? UUID()
    }
}
