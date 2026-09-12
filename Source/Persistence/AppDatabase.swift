import CalendarCountdownCore
import Foundation
import GRDB

public struct AppDatabase: Sendable {
    public let pool: DatabasePool
    public let path: String
    public let deviceID: UUID

    public static let schemaVersion = 1

    public static func open(
        at url: URL,
        backupDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> AppDatabase {
        try AppDatabasePoolRegistry.shared.intern(path: url.standardizedFileURL.path) {
            try openUncached(
                at: url,
                backupDirectory: backupDirectory,
                fileManager: fileManager
            )
        }
    }

    public static func openSharedContainer(fileManager: FileManager = .default) throws -> AppDatabase {
        let registry = try CloudProfileRegistry.shared(fileManager: fileManager)
        let database = try open(
            at: registry.activeDatabaseURL(),
            backupDirectory: registry.backupDirectoryURL,
            fileManager: fileManager
        )
        try CountdownService(db: database).importLegacyJSONIfNeeded(fileManager: fileManager)
        return database
    }

    public static func openTemporary(fileManager: FileManager = .default) throws -> AppDatabase {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("cc-db-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try open(
            at: directory.appendingPathComponent("calendarcountdown-v2.sqlite"),
            backupDirectory: directory.appendingPathComponent("Backups", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func write<T>(_ updates: @Sendable (Database) throws -> T) throws -> T {
        try pool.write(updates)
    }

    public func read<T>(_ value: @Sendable (Database) throws -> T) throws -> T {
        try pool.read(value)
    }

    public func checkIntegrity() throws {
        let result = try read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check")
        }
        guard result?.lowercased() == "ok" else {
            DiagnosticLogger.shared.log(
                .fault,
                category: .database,
                event: "database.integrity.failed",
                metadata: ["result": result ?? "unknown"]
            )
            throw DomainError(
                code: .sqliteIntegrity,
                message: "SQLite integrity check failed: \(result ?? "unknown").",
                details: ["result": result ?? "unknown"]
            )
        }
        DiagnosticLogger.shared.log(.debug, category: .database, event: "database.integrity.completed")
    }

    public func backup(to directory: URL, fileManager: FileManager = .default) throws -> URL {
        try SQLiteFilePolicy.protectDirectory(directory, fileManager: fileManager)
        let stamp = RFC3339.utcString(from: Date()).replacingOccurrences(of: ":", with: "")
        let destination = directory.appendingPathComponent("calendarcountdown-v2-\(stamp).sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        let destinationPool = try DatabasePool(path: destination.path, configuration: config)
        try pool.backup(to: destinationPool)
        try destinationPool.close()
        try SQLiteFilePolicy.protectDatabase(at: destination, fileManager: fileManager)
        return destination
    }

    public func copyContents(to destination: AppDatabase) throws {
        try pool.backup(to: destination.pool)
    }

    public func close() throws {
        AppDatabasePoolRegistry.shared.remove(path: path)
        try pool.close()
    }

    private static func openUncached(
        at url: URL,
        backupDirectory: URL?,
        fileManager: FileManager
    ) throws -> AppDatabase {
        let started = Date()
        DiagnosticLogger.shared.log(
            .info,
            category: .database,
            event: "database.open.started",
            metadata: ["database_file": url.lastPathComponent]
        )
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try SQLiteFilePolicy.protectDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
            var config = Configuration()
            config.busyMode = .timeout(5)
            config.foreignKeysEnabled = true
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA busy_timeout = 5000")
                try SQLiteFilePolicy.protectDatabase(at: url, fileManager: .default)
            }
            let pool = try DatabasePool(path: url.path, configuration: config)
            let database = AppDatabase(pool: pool, path: url.path, deviceID: UUID())
            let backups = try backupDirectory ?? SharedContainer.sqliteBackupDirectoryURL(fileManager: fileManager)
            try SQLiteFilePolicy.protectDirectory(backups, fileManager: fileManager)
            try database.migrate(backingUpTo: backups)
            try SQLiteFilePolicy.protectDatabase(at: url, fileManager: fileManager)
            let deviceID = try database.ensureDeviceID()
            try database.ensureProjectionSettings(deviceID: deviceID)
            try database.checkIntegrity()
            DiagnosticLogger.shared.setLocalDeviceID(deviceID)
            DiagnosticLogger.shared.log(
                .notice,
                category: .database,
                event: "database.open.completed",
                metadata: [
                    "database_file": url.lastPathComponent,
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                    "schema_version": String(schemaVersion)
                ]
            )
            return AppDatabase(pool: pool, path: url.path, deviceID: deviceID)
        } catch {
            DiagnosticLogger.shared.log(
                .fault,
                category: .database,
                event: "database.open.failed",
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "database_file": url.lastPathComponent,
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000))
                ]) { current, _ in current }
            )
            throw error
        }
    }

    private func migrate(backingUpTo backupDirectory: URL) throws {
        let migrator = DatabaseMigrations.make()
        let applied = try pool.read { db -> [String] in
            let exists = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'grdb_migrations'"
            ) ?? 0) > 0
            guard exists else { return [] }
            return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        let pending = migrator.migrations.filter { !applied.contains($0) }
        if !applied.isEmpty && !pending.isEmpty {
            let backupURL = try backup(to: backupDirectory)
            DiagnosticLogger.shared.log(
                .notice,
                category: .database,
                event: "database.migration.backup_created",
                metadata: [
                    "backup_file": backupURL.lastPathComponent,
                    "pending_count": String(pending.count)
                ]
            )
        }
        DiagnosticLogger.shared.log(
            .info,
            category: .database,
            event: "database.migration.started",
            metadata: [
                "applied_count": String(applied.count),
                "pending_count": String(pending.count)
            ]
        )
        do {
            try migrator.migrate(pool)
            DiagnosticLogger.shared.log(
                .notice,
                category: .database,
                event: "database.migration.completed",
                metadata: ["applied_now": String(pending.count)]
            )
        } catch {
            DiagnosticLogger.shared.log(
                .fault,
                category: .database,
                event: "database.migration.failed",
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "pending_count": String(pending.count)
                ]) { current, _ in current }
            )
            throw DomainError(
                code: .sqliteMigrationFailed,
                message: "数据库迁移失败：\(error.localizedDescription)",
                details: ["pending": pending.joined(separator: ",")],
                retryable: false
            )
        }
    }

    private func ensureDeviceID() throws -> UUID {
        try write { db in
            if let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM local_kv WHERE key = ?",
                arguments: ["device_id"]
            ), let uuid = UUID(uuidString: value) {
                return uuid
            }
            let uuid = UUID()
            try db.execute(
                sql: "INSERT INTO local_kv(key, value) VALUES (?, ?)",
                arguments: ["device_id", uuid.uuidString.lowercased()]
            )
            return uuid
        }
    }

    private func ensureProjectionSettings(deviceID: UUID) throws {
        try write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projection_settings") ?? 0
            guard count == 0 else { return }
            let settings = ProjectionSettings.default(deviceID: deviceID)
            try ProjectionSettingsRow(settings).insert(db)
        }
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
        #if os(macOS)
        // Group containers are already outside normal user backup scope on macOS.
        // On some installations, asking Foundation to reapply this metadata to
        // their contents can block in getxattr/open for minutes and make the app
        // look frozen. iOS data protection remains applied below.
        let localGroupPath = "/Library/Group Containers/\(ProductConstants.appGroupIdentifier)/"
        if url.path.contains(localGroupPath) {
            return
        }
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
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

enum SQLValue {
    static func uuid(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    static func uuid(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw DomainError.validation("无效的 UUID：\(value)。")
        }
        return uuid
    }

    static func date(_ value: Date?) -> String? {
        value.map(RFC3339.utcString(from:))
    }

    static func date(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        return try RFC3339.parseRequired(value)
    }

    static func requiredDate(_ value: String) throws -> Date {
        try RFC3339.parseRequired(value)
    }

    static func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func decimal(_ value: String) throws -> Decimal {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DomainError.validation("无效的小数：\(value)。")
        }
        return decimal
    }

    static func json<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONCoding.encoder(pretty: false).encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func json<T: Decodable>(_ type: T.Type, _ value: String?) throws -> T? {
        guard let value, !value.isEmpty else { return nil }
        return try JSONCoding.decoder().decode(type, from: Data(value.utf8))
    }
}
