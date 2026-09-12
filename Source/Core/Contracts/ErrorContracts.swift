import Foundation

public enum DomainErrorCode: String, Codable, Sendable, CaseIterable {
    case taskNotFound = "task_not_found"
    case occurrenceNotFound = "occurrence_not_found"
    case missionNotFound = "mission_not_found"
    case habitNotFound = "habit_not_found"
    case checkInNotFound = "checkin_not_found"
    case revisionConflict = "revision_conflict"
    case validationFailed = "validation_failed"
    case idempotencyConflict = "idempotency_conflict"
    case unknownArgument = "unknown_argument"
    case sqliteIntegrity = "sqlite_integrity"
    case sqliteMigrationFailed = "sqlite_migration_failed"
    case calendarAccessRequired = "calendar_access_required"
    case remindersAccessRequired = "reminders_access_required"
    case icloudUnavailable = "icloud_unavailable"
    case conflict = "conflict"
    case notImplemented = "not_implemented"
    case usage = "usage_error"
    case operationFailed = "operation_failed"
    case databaseUnavailable = "database_unavailable"
    case brokerUnavailable = "broker_unavailable"
    case brokerAuthFailed = "broker_auth_failed"
    case projectionFailed = "projection_failed"
}

public struct DomainError: Error, Equatable, LocalizedError, Codable, Sendable {
    public var code: DomainErrorCode
    public var message: String
    public var details: [String: String]
    public var retryable: Bool

    public init(
        code: DomainErrorCode,
        message: String,
        details: [String: String] = [:],
        retryable: Bool = false
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.retryable = retryable
    }

    public var errorDescription: String? { message }

    public static func validation(
        _ message: String,
        details: [String: String] = [:]
    ) -> DomainError {
        DomainError(code: .validationFailed, message: message, details: details)
    }

    public static func notFound(_ code: DomainErrorCode, id: UUID) -> DomainError {
        DomainError(
            code: code,
            message: "找不到对象：\(id.uuidString.lowercased())。",
            details: ["id": id.uuidString.lowercased()]
        )
    }

    public static func revisionConflict(expected: Int64, actual: Int64) -> DomainError {
        DomainError(
            code: .revisionConflict,
            message: "修订冲突：期望 \(expected)，实际 \(actual)。",
            details: [
                "expectedRevision": String(expected),
                "actualRevision": String(actual)
            ]
        )
    }
}

public struct APIMeta: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestId: UUID
    public var revision: String?

    public init(schemaVersion: Int = 2, requestId: UUID = UUID(), revision: String? = nil) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.revision = revision
    }
}

public struct APIErrorPayload: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var details: [String: String]
    public var retryable: Bool

    public init(code: String, message: String, details: [String: String] = [:], retryable: Bool = false) {
        self.code = code
        self.message = message
        self.details = details
        self.retryable = retryable
    }

    public init(_ error: DomainError) {
        self.init(
            code: error.code.rawValue,
            message: error.message,
            details: error.details,
            retryable: error.retryable
        )
    }
}

public struct APIEnvelope<T: Codable & Sendable>: Codable, Sendable {
    public var ok: Bool
    public var data: T?
    public var error: APIErrorPayload?
    public var meta: APIMeta

    public init(ok: Bool, data: T? = nil, error: APIErrorPayload? = nil, meta: APIMeta) {
        self.ok = ok
        self.data = data
        self.error = error
        self.meta = meta
    }

    public static func success(_ data: T, meta: APIMeta = APIMeta()) -> APIEnvelope<T> {
        APIEnvelope(ok: true, data: data, meta: meta)
    }

    public static func failure(_ error: DomainError, requestId: UUID) -> APIEnvelope<T> {
        APIEnvelope(
            ok: false,
            error: APIErrorPayload(error),
            meta: APIMeta(requestId: requestId)
        )
    }
}

public enum CLIExitCode {
    public static let success: Int32 = 0
    public static let general: Int32 = 1
    public static let usage: Int32 = 64
    public static let conflict: Int32 = 73
    public static let permission: Int32 = 77

    public static func forDomain(_ error: DomainError) -> Int32 {
        switch error.code {
        case .usage, .unknownArgument, .validationFailed:
            usage
        case .calendarAccessRequired, .remindersAccessRequired, .brokerAuthFailed:
            permission
        case .brokerUnavailable:
            general
        case .revisionConflict, .conflict, .idempotencyConflict:
            conflict
        default:
            general
        }
    }
}
