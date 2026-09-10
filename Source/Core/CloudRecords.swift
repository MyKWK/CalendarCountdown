import Foundation

public enum CloudKitSchema {
    public static let zoneName = "CalendarCountdownZone"
    public static let recordTypes = [
        "CDMission",
        "CDTaskSeries",
        "CDTaskOccurrence",
        "CDHabit",
        "CDHabitPeriod",
        "CDCheckIn",
        "CDManagedEvent",
        "CDCountdownSelection",
        "CDCountdownPreferences",
        "CDProjectionSettings",
        "CDProjectionLease",
        "CDTombstone"
    ]

    public static let applyOrder = [
        "CDMission",
        "CDTaskSeries",
        "CDTaskOccurrence",
        "CDHabit",
        "CDHabitPeriod",
        "CDCheckIn",
        "CDManagedEvent",
        "CDCountdownSelection",
        "CDCountdownPreferences",
        "CDProjectionSettings",
        "CDProjectionLease"
    ]
}

public enum CloudSyncMode: String, Codable, CaseIterable, Sendable {
    case localOnly
    case iCloud
}

public enum CloudFetchOutcome: String, Sendable {
    case applied
    case empty
    case failed
}

public enum CloudRecordIdentity {
    public static let countdownPreferences = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee1")!
}

public struct CloudOutboxItem: Equatable, Sendable {
    public var id: UUID
    public var recordType: String
    public var recordName: UUID
    public var operation: String
    public var revision: Int64
    public var payloadJSON: String
    public var modifiedByDevice: UUID
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        recordType: String,
        recordName: UUID,
        operation: String,
        revision: Int64,
        payloadJSON: String,
        modifiedByDevice: UUID,
        updatedAt: Date
    ) {
        self.id = id
        self.recordType = recordType
        self.recordName = recordName
        self.operation = operation
        self.revision = revision
        self.payloadJSON = payloadJSON
        self.modifiedByDevice = modifiedByDevice
        self.updatedAt = updatedAt
    }
}
