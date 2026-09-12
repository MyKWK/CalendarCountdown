import Darwin
import Foundation
import OSLog

@_silgen_name("flock")
private func calendarCountdownFileLock(_ fileDescriptor: Int32, _ operation: Int32) -> Int32

public enum DiagnosticLogLevel: String, Codable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    fileprivate var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .warning: .error
        case .error: .error
        case .fault: .fault
        }
    }
}

public enum DiagnosticLogCategory: String, Codable, Sendable {
    case lifecycle
    case database
    case command
    case broker
    case calendar
    case projection
    case sync
    case widget
    case maintenance
}

/// One line in the local JSONL diagnostic stream. Log payloads intentionally
/// contain operational metadata only; command bodies, event titles and CloudKit
/// record payloads must never be written here.
public struct DiagnosticLogEntry: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let timestamp: String
    public let level: DiagnosticLogLevel
    public let category: DiagnosticLogCategory
    public let event: String
    public let message: String?
    public let component: String
    public let processID: Int32
    public let sessionID: UUID
    public let installationID: UUID
    public let localDeviceID: UUID?
    public let correlationID: UUID?
    public let metadata: [String: String]

    public init(
        schemaVersion: Int = 1,
        timestamp: String,
        level: DiagnosticLogLevel,
        category: DiagnosticLogCategory,
        event: String,
        message: String? = nil,
        component: String,
        processID: Int32,
        sessionID: UUID,
        installationID: UUID,
        localDeviceID: UUID? = nil,
        correlationID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.event = event
        self.message = message
        self.component = component
        self.processID = processID
        self.sessionID = sessionID
        self.installationID = installationID
        self.localDeviceID = localDeviceID
        self.correlationID = correlationID
        self.metadata = metadata
    }
}

public struct DiagnosticLogFile: Codable, Equatable, Sendable {
    public let name: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?

    public init(name: String, sizeBytes: Int64, modifiedAt: Date?) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

public struct DiagnosticLogStatus: Codable, Equatable, Sendable {
    public let directory: String
    public let retentionDays: Int
    public let localOnly: Bool
    public let excludedFromBackup: Bool
    public let files: [DiagnosticLogFile]

    public init(
        directory: String,
        retentionDays: Int,
        localOnly: Bool,
        excludedFromBackup: Bool,
        files: [DiagnosticLogFile]
    ) {
        self.directory = directory
        self.retentionDays = retentionDays
        self.localOnly = localOnly
        self.excludedFromBackup = excludedFromBackup
        self.files = files
    }
}

/// Synchronous, process-safe-in-practice JSONL writer. Every executable gets
/// its own component/date file, preventing App, CLI and Widget file contention.
public final class DiagnosticLogStore: @unchecked Sendable {
    public static let retentionDays = ProductConstants.diagnosticLogRetentionDays

    public let rootURL: URL
    public let component: String
    public let installationID: UUID
    private let fileManager: FileManager
    private let lock = NSLock()
    private var nextMaintenanceAt = Date.distantPast

    public init(
        rootURL: URL,
        component: String,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.component = Self.safeComponent(component)
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.rootURL.path)
        try Self.markLocalOnly(self.rootURL)
        self.installationID = try Self.loadOrCreateInstallationID(
            at: self.rootURL.appendingPathComponent("installation-id"),
            fileManager: fileManager
        )
    }

    public static func defaultRootURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("CalendarCountdown", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public func append(_ entry: DiagnosticLogEntry, at date: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        if date >= nextMaintenanceAt {
            _ = try cleanupLocked(referenceDate: date)
            nextMaintenanceAt = date.addingTimeInterval(24 * 60 * 60)
        }
        let url = logFileURL(for: date)
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try Self.markLocalOnly(url)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(entry)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        guard calendarCountdownFileLock(handle.fileDescriptor, LOCK_EX) == 0 else {
            throw CocoaError(.fileLocking)
        }
        defer { _ = calendarCountdownFileLock(handle.fileDescriptor, LOCK_UN) }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    @discardableResult
    public func cleanup(referenceDate: Date = Date()) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let removed = try cleanupLocked(referenceDate: referenceDate)
        nextMaintenanceAt = referenceDate.addingTimeInterval(24 * 60 * 60)
        return removed
    }

    public func files() throws -> [DiagnosticLogFile] {
        lock.lock()
        defer { lock.unlock() }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
        .map { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return DiagnosticLogFile(
                name: url.lastPathComponent,
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        }
        .sorted { $0.name > $1.name }
    }

    public func status() throws -> DiagnosticLogStatus {
        let values = try rootURL.resourceValues(forKeys: [.isUbiquitousItemKey, .isExcludedFromBackupKey])
        return DiagnosticLogStatus(
            directory: rootURL.path,
            retentionDays: Self.retentionDays,
            localOnly: values.isUbiquitousItem != true,
            excludedFromBackup: values.isExcludedFromBackup == true,
            files: try files()
        )
    }

    private func cleanupLocked(referenceDate: Date) throws -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let boundary = calendar.date(
            byAdding: .day,
            value: -(Self.retentionDays - 1),
            to: referenceDate
        ) else {
            return 0
        }
        let cutoff = calendar.startOfDay(for: boundary)
        var removed = 0
        let candidates = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in candidates where url.pathExtension == "jsonl" {
            guard let fileDate = Self.dateFromLogFileName(url.lastPathComponent), fileDate < cutoff else {
                continue
            }
            try fileManager.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    private func logFileURL(for date: Date) -> URL {
        rootURL.appendingPathComponent("calendarcountdown-\(component)-\(Self.dayString(date)).jsonl")
    }

    private static func loadOrCreateInstallationID(at url: URL, fileManager: FileManager) throws -> UUID {
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let value = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }
        let value = UUID()
        try value.uuidString.lowercased().write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try markLocalOnly(url)
        return value
    }

    private static func markLocalOnly(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "process" : result
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func dateFromLogFileName(_ name: String) -> Date? {
        guard name.hasPrefix("calendarcountdown-"), name.hasSuffix(".jsonl") else { return nil }
        let stem = String(name.dropLast(6))
        guard stem.count >= 10 else { return nil }
        let day = String(stem.suffix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }
}

public final class DiagnosticLogger: @unchecked Sendable {
    public static let shared = DiagnosticLogger()

    private let lock = NSLock()
    private var store: DiagnosticLogStore?
    private var component = DiagnosticLogger.defaultComponent
    private var localDeviceID: UUID?
    private let sessionID = UUID()

    private init() {}

    public func configure(
        component: String,
        localDeviceID: UUID? = nil,
        rootURL: URL? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.component = component
        self.localDeviceID = localDeviceID ?? self.localDeviceID
        do {
            store = try DiagnosticLogStore(
                rootURL: try rootURL ?? DiagnosticLogStore.defaultRootURL(),
                component: component
            )
        } catch {
            store = nil
            Logger(subsystem: ProductConstants.appBundleIdentifier, category: "maintenance")
                .error("diagnostic_store_unavailable error_type=\(String(reflecting: type(of: error)), privacy: .public)")
        }
    }

    public func setLocalDeviceID(_ value: UUID) {
        lock.lock()
        localDeviceID = value
        lock.unlock()
    }

    public func log(
        _ level: DiagnosticLogLevel,
        category: DiagnosticLogCategory,
        event: String,
        message: String? = nil,
        correlationID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        let snapshot: (DiagnosticLogStore?, String, UUID?)
        lock.lock()
        if store == nil && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store = try? DiagnosticLogStore(
                rootURL: DiagnosticLogStore.defaultRootURL(),
                component: component
            )
        }
        snapshot = (store, component, localDeviceID)
        lock.unlock()

        let cleanEvent = Self.sanitize(event, key: "event")
        let cleanMessage = message.map { Self.sanitize($0, key: "message") }
        let cleanMetadata = Dictionary(uniqueKeysWithValues: metadata.map {
            ($0.key, Self.sanitize($0.value, key: $0.key))
        })
        let installationID = snapshot.0?.installationID ?? UUID()
        let entry = DiagnosticLogEntry(
            timestamp: RFC3339.utcString(from: Date()),
            level: level,
            category: category,
            event: cleanEvent,
            message: cleanMessage,
            component: snapshot.1,
            processID: ProcessInfo.processInfo.processIdentifier,
            sessionID: sessionID,
            installationID: installationID,
            localDeviceID: snapshot.2,
            correlationID: correlationID,
            metadata: cleanMetadata
        )
        try? snapshot.0?.append(entry)

        let rendered = "\(cleanEvent) \(cleanMetadata)"
        Logger(subsystem: ProductConstants.appBundleIdentifier, category: category.rawValue)
            .log(level: level.osLogType, "\(rendered, privacy: .public)")
    }

    @discardableResult
    public func cleanup() throws -> Int {
        lock.lock()
        let current = store
        lock.unlock()
        guard let current else { return 0 }
        return try current.cleanup()
    }

    public func status() throws -> DiagnosticLogStatus {
        lock.lock()
        let current = store
        lock.unlock()
        guard let current else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try current.status()
    }

    public static func errorMetadata(_ error: Error) -> [String: String] {
        if let domain = error as? DomainError {
            return [
                "error_code": domain.code.rawValue,
                "retryable": String(domain.retryable),
                "error_type": String(reflecting: type(of: error))
            ]
        }
        let nsError = error as NSError
        return [
            "error_domain": nsError.domain,
            "error_code": String(nsError.code),
            "error_type": String(reflecting: type(of: error))
        ]
    }

    static func sanitize(_ value: String, key: String) -> String {
        let lowered = key.lowercased()
        if ["token", "secret", "password", "authorization", "payload", "params", "body"].contains(where: lowered.contains) {
            return "<redacted>"
        }
        var result = value
        let patterns = [
            "(?i)bearer\\s+[a-z0-9._~+/=-]+",
            "(?i)(token|secret|password|authorization)\\s*[:=]\\s*[^\\s,;]+"
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "<redacted>")
        }
        return String(result.prefix(2_048))
    }

    private static var defaultComponent: String {
        let identifier = Bundle.main.bundleIdentifier?.lowercased() ?? ""
        if identifier.contains("widget") { return "widget" }
        if identifier.contains("cli") || ProcessInfo.processInfo.processName == "calcount" { return "cli" }
        if identifier == ProductConstants.appBundleIdentifier.lowercased() { return "app" }
        return "process"
    }
}
