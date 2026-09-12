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

public struct CloudFieldSnapshot: Equatable, Codable, Sendable {
    public var value: String?
    public var hlc: String

    public init(value: String?, hlc: HybridLogicalTimestamp) {
        self.value = value
        self.hlc = hlc.wireValue
    }

    public init(value: String?, hlc: String) {
        self.value = value
        self.hlc = hlc
    }

    public func snapshot() -> FieldSnapshot? {
        guard let parsed = HybridLogicalTimestamp.parse(hlc) else { return nil }
        return FieldSnapshot(value: value, hlc: parsed)
    }
}

public struct CloudRecordEnvelope: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var recordType: String
    public var recordName: UUID
    public var operation: String
    public var revision: Int64
    public var payloadJSON: String
    public var fields: [String: CloudFieldSnapshot]
    public var modifiedByDevice: UUID
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        recordType: String,
        recordName: UUID,
        operation: String,
        revision: Int64,
        payloadJSON: String,
        fields: [String: CloudFieldSnapshot] = [:],
        modifiedByDevice: UUID,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.recordType = recordType
        self.recordName = recordName
        self.operation = operation
        self.revision = revision
        self.payloadJSON = payloadJSON
        self.fields = fields
        self.modifiedByDevice = modifiedByDevice
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var fieldSnapshots: [String: FieldSnapshot] {
        var result: [String: FieldSnapshot] = [:]
        for (name, payload) in fields {
            if let snapshot = payload.snapshot() {
                result[name] = snapshot
            }
        }
        return result
    }
}

public struct CloudApplyReport: Equatable, Codable, Sendable {
    public var applied: Int
    public var created: Int
    public var updated: Int
    public var conflicts: Int
    public var skipped: Int
    public var failed: Int
    public var pendingInbox: Int
    public var conflictSummaries: [String]
    public var lastFetchAdvanced: Bool

    public init(
        applied: Int = 0,
        created: Int = 0,
        updated: Int = 0,
        conflicts: Int = 0,
        skipped: Int = 0,
        failed: Int = 0,
        pendingInbox: Int = 0,
        conflictSummaries: [String] = [],
        lastFetchAdvanced: Bool = false
    ) {
        self.applied = applied
        self.created = created
        self.updated = updated
        self.conflicts = conflicts
        self.skipped = skipped
        self.failed = failed
        self.pendingInbox = pendingInbox
        self.conflictSummaries = conflictSummaries
        self.lastFetchAdvanced = lastFetchAdvanced
    }
}

public struct CloudBundle: Equatable, Codable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var records: [CloudRecordEnvelope]

    public init(schemaVersion: Int = 2, exportedAt: Date = Date(), records: [CloudRecordEnvelope]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.records = records
    }
}

public enum CloudAccountStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case signedOut
    case switched
}

public struct CloudSyncStatus: Equatable, Codable, Sendable {
    public var mode: CloudSyncMode
    public var account: CloudAccountStatus
    public var zoneName: String
    public var pendingOutbox: Int
    public var openConflicts: Int
    public var lastFetchAt: Date?
    public var lastSendAt: Date?
    public var hasSerializedState: Bool
    public var accountIdentifierHash: String?
    public var pendingInbox: Int

    public init(
        mode: CloudSyncMode,
        account: CloudAccountStatus = .unknown,
        zoneName: String = CloudKitSchema.zoneName,
        pendingOutbox: Int,
        openConflicts: Int,
        lastFetchAt: Date? = nil,
        lastSendAt: Date? = nil,
        hasSerializedState: Bool = false,
        accountIdentifierHash: String? = nil,
        pendingInbox: Int = 0
    ) {
        self.mode = mode
        self.account = account
        self.zoneName = zoneName
        self.pendingOutbox = pendingOutbox
        self.openConflicts = openConflicts
        self.lastFetchAt = lastFetchAt
        self.lastSendAt = lastSendAt
        self.hasSerializedState = hasSerializedState
        self.accountIdentifierHash = accountIdentifierHash
        self.pendingInbox = pendingInbox
    }
}

public struct CloudExportReport: Equatable, Codable, Sendable {
    public var exportedPath: String?
    public var recordCount: Int
    public var acked: Int
    public var skipped: Int
    public var outboxIDs: [String]

    public init(
        exportedPath: String? = nil,
        recordCount: Int,
        acked: Int = 0,
        skipped: Int = 0,
        outboxIDs: [String] = []
    ) {
        self.exportedPath = exportedPath
        self.recordCount = recordCount
        self.acked = acked
        self.skipped = skipped
        self.outboxIDs = outboxIDs
    }
}

public struct ProjectionReconcileReport: Equatable, Codable, Sendable {
    public var desired: Int
    public var applied: Int
    public var reverseActions: Int
    public var missing: Int
    public var drifted: Int
    public var failed: Int
    public var pendingCompleted: Int
    public var errors: [String]
    public var dryRun: Bool

    public init(
        desired: Int = 0,
        applied: Int = 0,
        reverseActions: Int = 0,
        missing: Int = 0,
        drifted: Int = 0,
        failed: Int = 0,
        pendingCompleted: Int = 0,
        errors: [String] = [],
        dryRun: Bool = false
    ) {
        self.desired = desired
        self.applied = applied
        self.reverseActions = reverseActions
        self.missing = missing
        self.drifted = drifted
        self.failed = failed
        self.pendingCompleted = pendingCompleted
        self.errors = errors
        self.dryRun = dryRun
    }
}

extension Notification.Name {
    public static let calendarCountdownCloudDidApply = Notification.Name(
        "CalendarCountdown.cloudDidApply"
    )
    public static let calendarCountdownWorkspaceDidChange = Notification.Name(
        "CalendarCountdown.workspaceDidChange"
    )
}
