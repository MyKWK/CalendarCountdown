import Foundation

public struct CloudManagedEventDraft: Codable, Equatable, Sendable {
    public var externalId: String?
    public var title: String
    public var calendarTitle: String?
    public var calendarSystem: CalendarSystemKind
    public var recurrence: RecurrenceKind
    public var date: String?
    public var time: String?
    public var startYear: Int?
    public var lunarMonth: Int?
    public var lunarDay: Int?
    public var lunarLeapMonthPolicy: LunarLeapMonthPolicy
    public var invalidLunarDayPolicy: InvalidLunarDayPolicy
    public var isAllDay: Bool
    public var alertDaysBefore: [Int]
    public var notes: String?
    public var selectForCountdown: Bool

    public init(_ draft: ManagedEventDraft) {
        externalId = draft.externalId
        title = draft.title
        calendarTitle = draft.calendarTitle
        calendarSystem = draft.calendarSystem
        recurrence = draft.recurrence
        date = draft.date
        time = draft.time
        startYear = draft.startYear
        lunarMonth = draft.lunarMonth
        lunarDay = draft.lunarDay
        lunarLeapMonthPolicy = draft.lunarLeapMonthPolicy
        invalidLunarDayPolicy = draft.invalidLunarDayPolicy
        isAllDay = draft.isAllDay
        alertDaysBefore = draft.alertDaysBefore
        notes = draft.notes
        selectForCountdown = draft.selectForCountdown
    }
}

public struct CountdownManagedCloudPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var draft: CloudManagedEventDraft
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(_ record: ManagedEventRecord) {
        id = record.id
        draft = CloudManagedEventDraft(record.draft)
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        revision = record.revision
        modifiedByDevice = record.modifiedByDevice
        deletedAt = record.deletedAt
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
