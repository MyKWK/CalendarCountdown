import Foundation

public struct CountdownManagedCloudPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var draft: ManagedEventDraft
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID,
        draft: ManagedEventDraft,
        createdAt: Date,
        updatedAt: Date,
        revision: Int64,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        var cloudDraft = draft
        cloudDraft.calendarIdentifier = nil
        self.draft = cloudDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }

    public init(_ record: ManagedEventRecord) {
        self.init(
            id: record.id,
            draft: record.draft,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            modifiedByDevice: record.modifiedByDevice,
            deletedAt: record.deletedAt
        )
    }
}

public struct CountdownSelectionCloudPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var mode: SelectionMode
    public var calendarTitle: String
    public var eventTitle: String
    public var externalIdentifier: String?
    public var managedRecordID: UUID?
    public var occurrenceDate: Date?
    public var selectedAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(_ selection: CountdownSelection) {
        id = selection.id
        mode = selection.mode
        calendarTitle = selection.calendarTitle
        eventTitle = selection.eventTitle
        externalIdentifier = selection.externalIdentifier
        managedRecordID = selection.managedRecordID
        occurrenceDate = selection.occurrenceDate
        selectedAt = selection.selectedAt
        updatedAt = selection.updatedAt
        revision = selection.revision
        modifiedByDevice = selection.modifiedByDevice
        deletedAt = selection.deletedAt
    }
}

public struct CountdownPreferencesCloudPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var pinnedSelectionID: UUID?
    public var revision: Int64
    public var updatedAt: Date
    public var modifiedByDevice: UUID

    public init(
        id: UUID,
        pinnedSelectionID: UUID?,
        revision: Int64,
        updatedAt: Date,
        modifiedByDevice: UUID
    ) {
        self.id = id
        self.pinnedSelectionID = pinnedSelectionID
        self.revision = revision
        self.updatedAt = updatedAt
        self.modifiedByDevice = modifiedByDevice
    }
}
