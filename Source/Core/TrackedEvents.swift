import Foundation

public enum TrackedEventKind: String, Codable, CaseIterable, Sendable {
    case birthday
    case anniversary
    case importantDate
    case other
}

public enum TrackedRecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case none
    case daily
    case weekly
    case monthly
    case yearly
    case unknown
}

public struct TrackedDateDefinition: Codable, Equatable, Sendable {
    /// The Gregorian year in which the important date started. For a lunar
    /// date, month/day still use the Chinese lunar calendar.
    public let startYear: Int
    public let calendarSystem: CalendarSystemKind
    public let month: Int
    public let day: Int
    public let isLeapMonth: Bool?

    public init(
        startYear: Int,
        calendarSystem: CalendarSystemKind,
        month: Int,
        day: Int,
        isLeapMonth: Bool? = nil
    ) {
        self.startYear = startYear
        self.calendarSystem = calendarSystem
        self.month = month
        self.day = day
        self.isLeapMonth = isLeapMonth
    }
}

public struct TrackedRecurrenceDefinition: Codable, Equatable, Sendable {
    public let frequency: TrackedRecurrenceFrequency
    public let calendarSystem: CalendarSystemKind
    public let lunarLeapMonthPolicy: LunarLeapMonthPolicy?
    public let invalidLunarDayPolicy: InvalidLunarDayPolicy?

    public init(
        frequency: TrackedRecurrenceFrequency,
        calendarSystem: CalendarSystemKind,
        lunarLeapMonthPolicy: LunarLeapMonthPolicy? = nil,
        invalidLunarDayPolicy: InvalidLunarDayPolicy? = nil
    ) {
        self.frequency = frequency
        self.calendarSystem = calendarSystem
        self.lunarLeapMonthPolicy = lunarLeapMonthPolicy
        self.invalidLunarDayPolicy = invalidLunarDayPolicy
    }
}

public struct TrackedCalendarReference: Codable, Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let sourceTitle: String
    public let colorHex: String

    public init(identifier: String, title: String, sourceTitle: String, colorHex: String) {
        self.identifier = identifier
        self.title = title
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
    }
}

public struct TrackedSelectionReference: Codable, Equatable, Sendable {
    public let mode: SelectionMode
    public let trackedSince: Date
    public let isPinned: Bool

    public init(mode: SelectionMode, trackedSince: Date, isPinned: Bool) {
        self.mode = mode
        self.trackedSince = trackedSince
        self.isPinned = isPinned
    }
}

public struct TrackedAppleCalendarReference: Codable, Equatable, Sendable {
    public let calendarItemIdentifier: String?
    public let externalIdentifier: String?
    public let managedRecordID: UUID?

    public init(
        calendarItemIdentifier: String?,
        externalIdentifier: String?,
        managedRecordID: UUID?
    ) {
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
        self.managedRecordID = managedRecordID
    }
}

public struct TrackedEventRecord: Codable, Identifiable, Equatable, Sendable {
    /// Reuses the selection UUID so the record stays stable between refreshes.
    public let id: UUID
    public let title: String
    public let kind: TrackedEventKind
    public let date: TrackedDateDefinition
    public let recurrence: TrackedRecurrenceDefinition
    public let nextOccurrence: String?
    public let time: String?
    public let timeZoneIdentifier: String
    public let isAllDay: Bool
    public let calendar: TrackedCalendarReference
    public let tracking: TrackedSelectionReference
    public let appleCalendar: TrackedAppleCalendarReference

    public init(
        id: UUID,
        title: String,
        kind: TrackedEventKind,
        date: TrackedDateDefinition,
        recurrence: TrackedRecurrenceDefinition,
        nextOccurrence: String?,
        time: String?,
        timeZoneIdentifier: String,
        isAllDay: Bool,
        calendar: TrackedCalendarReference,
        tracking: TrackedSelectionReference,
        appleCalendar: TrackedAppleCalendarReference
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.date = date
        self.recurrence = recurrence
        self.nextOccurrence = nextOccurrence
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.tracking = tracking
        self.appleCalendar = appleCalendar
    }
}

public struct TrackedEventsDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceOfTruth: String
    public let updatedAt: Date
    public let events: [TrackedEventRecord]

    public init(
        schemaVersion: Int = 1,
        sourceOfTruth: String = "appleCalendar",
        updatedAt: Date = Date(),
        events: [TrackedEventRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.sourceOfTruth = sourceOfTruth
        self.updatedAt = updatedAt
        self.events = events
    }

    public static let empty = TrackedEventsDocument(updatedAt: .distantPast, events: [])
}

public enum TrackedEventsFileStore {
    public static func load(fileManager: FileManager = .default) throws -> TrackedEventsDocument {
        let url = try SharedContainer.trackedEventsURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return .empty }
        return try JSONCoding.decoder().decode(TrackedEventsDocument.self, from: Data(contentsOf: url))
    }

    public static func save(
        _ document: TrackedEventsDocument,
        fileManager: FileManager = .default
    ) throws {
        let url = try SharedContainer.trackedEventsURL(fileManager: fileManager)
        try export(document, to: url)
    }

    public static func export(_ document: TrackedEventsDocument, to url: URL) throws {
        try JSONCoding.encoder().encode(document).write(to: url, options: .atomic)
    }
}
