import Foundation

public enum CalendarSystemKind: String, Codable, CaseIterable, Sendable {
    case gregorian
    case lunar

    public var displayName: String {
        switch self {
        case .gregorian:
            AppLocalization.text("calendar_system.gregorian", defaultValue: "公历")
        case .lunar:
            AppLocalization.text("calendar_system.lunar", defaultValue: "农历")
        }
    }
}

public enum RecurrenceKind: String, Codable, CaseIterable, Sendable {
    case none
    case yearly
}

public enum LunarLeapMonthPolicy: String, Codable, CaseIterable, Sendable {
    case regularOnly
    case leapOnly
    case both
}

public enum InvalidLunarDayPolicy: String, Codable, CaseIterable, Sendable {
    case strict
    case clampToMonthEnd
}

public struct ManagedEventDraft: Codable, Equatable, Sendable {
    public var externalId: String?
    public var title: String
    public var calendarTitle: String?
    public var calendarIdentifier: String?
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

    public init(
        externalId: String? = nil,
        title: String,
        calendarTitle: String? = nil,
        calendarIdentifier: String? = nil,
        calendarSystem: CalendarSystemKind = .gregorian,
        recurrence: RecurrenceKind = .none,
        date: String? = nil,
        time: String? = nil,
        startYear: Int? = nil,
        lunarMonth: Int? = nil,
        lunarDay: Int? = nil,
        lunarLeapMonthPolicy: LunarLeapMonthPolicy = .regularOnly,
        invalidLunarDayPolicy: InvalidLunarDayPolicy = .clampToMonthEnd,
        isAllDay: Bool = true,
        alertDaysBefore: [Int] = [],
        notes: String? = nil,
        selectForCountdown: Bool = true
    ) {
        self.externalId = externalId
        self.title = title
        self.calendarTitle = calendarTitle
        self.calendarIdentifier = calendarIdentifier
        self.calendarSystem = calendarSystem
        self.recurrence = recurrence
        self.date = date
        self.time = time
        self.startYear = startYear
        self.lunarMonth = lunarMonth
        self.lunarDay = lunarDay
        self.lunarLeapMonthPolicy = lunarLeapMonthPolicy
        self.invalidLunarDayPolicy = invalidLunarDayPolicy
        self.isAllDay = isAllDay
        self.alertDaysBefore = alertDaysBefore
        self.notes = notes
        self.selectForCountdown = selectForCountdown
    }

    private enum CodingKeys: String, CodingKey {
        case externalId
        case title
        case calendarTitle
        case calendarIdentifier
        case calendarSystem
        case recurrence
        case date
        case time
        case startYear
        case lunarMonth
        case lunarDay
        case lunarLeapMonthPolicy
        case invalidLunarDayPolicy
        case isAllDay
        case alertDaysBefore
        case notes
        case selectForCountdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        title = try container.decode(String.self, forKey: .title)
        calendarTitle = try container.decodeIfPresent(String.self, forKey: .calendarTitle)
        calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier)
        calendarSystem = try container.decodeIfPresent(CalendarSystemKind.self, forKey: .calendarSystem) ?? .gregorian
        recurrence = try container.decodeIfPresent(RecurrenceKind.self, forKey: .recurrence) ?? .none
        date = try container.decodeIfPresent(String.self, forKey: .date)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        startYear = try container.decodeIfPresent(Int.self, forKey: .startYear)
        lunarMonth = try container.decodeIfPresent(Int.self, forKey: .lunarMonth)
        lunarDay = try container.decodeIfPresent(Int.self, forKey: .lunarDay)
        lunarLeapMonthPolicy = try container.decodeIfPresent(LunarLeapMonthPolicy.self, forKey: .lunarLeapMonthPolicy) ?? .regularOnly
        invalidLunarDayPolicy = try container.decodeIfPresent(InvalidLunarDayPolicy.self, forKey: .invalidLunarDayPolicy) ?? .clampToMonthEnd
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? true
        alertDaysBefore = try container.decodeIfPresent([Int].self, forKey: .alertDaysBefore) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        selectForCountdown = try container.decodeIfPresent(Bool.self, forKey: .selectForCountdown) ?? true
    }

    public func validated() throws -> ManagedEventDraft {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.calendarTitle = calendarTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.calendarIdentifier = calendarIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.externalId = externalId?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.alertDaysBefore = Array(Set(alertDaysBefore)).sorted(by: >)

        guard !copy.title.isEmpty else {
            throw ManagedEventValidationError.emptyTitle
        }
        guard !(copy.calendarTitle?.isEmpty ?? true) || !(copy.calendarIdentifier?.isEmpty ?? true) else {
            throw ManagedEventValidationError.missingDestinationCalendar
        }
        guard copy.alertDaysBefore.allSatisfy({ $0 >= 0 && $0 <= 3650 }) else {
            throw ManagedEventValidationError.invalidAlertDays
        }
        if let startYear = copy.startYear, !(1...9999).contains(startYear) {
            throw ManagedEventValidationError.invalidStartYear(startYear)
        }

        switch copy.calendarSystem {
        case .gregorian:
            guard let date = copy.date, DateSupport.parseDateOnly(date) != nil else {
                throw ManagedEventValidationError.invalidGregorianDate(copy.date)
            }
            copy.startYear = Int(date.prefix(4))
            if let time = copy.time, DateSupport.parseTime(time) == nil {
                throw ManagedEventValidationError.invalidTime(time)
            }
        case .lunar:
            guard copy.recurrence == .yearly else {
                throw ManagedEventValidationError.lunarMustRepeatYearly
            }
            guard let month = copy.lunarMonth, (1...12).contains(month) else {
                throw ManagedEventValidationError.invalidLunarMonth(copy.lunarMonth)
            }
            guard let day = copy.lunarDay, (1...30).contains(day) else {
                throw ManagedEventValidationError.invalidLunarDay(copy.lunarDay)
            }
        }
        return copy
    }
}

public enum ManagedEventValidationError: LocalizedError, Equatable {
    case emptyTitle
    case missingDestinationCalendar
    case invalidAlertDays
    case invalidStartYear(Int)
    case invalidGregorianDate(String?)
    case invalidTime(String)
    case lunarMustRepeatYearly
    case invalidLunarMonth(Int?)
    case invalidLunarDay(Int?)
    case invalidSelection

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            AppLocalization.text("error.empty_title", defaultValue: "事件标题不能为空。")
        case .missingDestinationCalendar:
            AppLocalization.text(
                "error.missing_destination_calendar",
                defaultValue: "必须提供目标 Apple 日历的 calendarTitle 或 calendarIdentifier。"
            )
        case .invalidAlertDays:
            AppLocalization.text(
                "error.invalid_alert_days",
                defaultValue: "提前提醒天数必须在 0 到 3650 之间。"
            )
        case let .invalidStartYear(value):
            AppLocalization.format(
                "error.invalid_start_year",
                defaultValue: "无效的开始年份：%lld，应为 1 到 9999。",
                Int64(value)
            )
        case let .invalidGregorianDate(value):
            AppLocalization.format(
                "error.invalid_gregorian_date",
                defaultValue: "无效的公历日期：%@，应为 YYYY-MM-DD。",
                value ?? AppLocalization.text("common.not_provided", defaultValue: "未提供")
            )
        case let .invalidTime(value):
            AppLocalization.format(
                "error.invalid_time",
                defaultValue: "无效的时间：%@，应为 HH:mm。",
                value
            )
        case .lunarMustRepeatYearly:
            AppLocalization.text(
                "error.lunar_requires_yearly",
                defaultValue: "农历事件必须使用 yearly 重复规则。"
            )
        case let .invalidLunarMonth(value):
            AppLocalization.format(
                "error.invalid_lunar_month",
                defaultValue: "无效的农历月份：%@。",
                value.map(String.init)
                    ?? AppLocalization.text("common.not_provided", defaultValue: "未提供")
            )
        case let .invalidLunarDay(value):
            AppLocalization.format(
                "error.invalid_lunar_day",
                defaultValue: "无效的农历日期：%@。",
                value.map(String.init)
                    ?? AppLocalization.text("common.not_provided", defaultValue: "未提供")
            )
        case .invalidSelection:
            AppLocalization.text(
                "error.invalid_selection",
                defaultValue: "倒数选择必须同时包含 Apple 日历名称和事件标题。"
            )
        }
    }
}

public struct ManagedEventRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var draft: ManagedEventDraft
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), draft: ManagedEventDraft, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.draft = draft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ImportDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var events: [ManagedEventDraft]
    public var selections: [SelectionDraft]

    public init(schemaVersion: Int = 1, events: [ManagedEventDraft], selections: [SelectionDraft] = []) {
        self.schemaVersion = schemaVersion
        self.events = events
        self.selections = selections
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case events
        case selections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        events = try container.decodeIfPresent([ManagedEventDraft].self, forKey: .events) ?? []
        selections = try container.decodeIfPresent([SelectionDraft].self, forKey: .selections) ?? []
    }

    public func validated() throws -> ImportDocument {
        guard schemaVersion == 1 else {
            throw ImportValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        let validatedEvents = try events.map { try $0.validated() }
        let externalIds = validatedEvents.compactMap(\.externalId)
        guard Set(externalIds).count == externalIds.count else {
            throw ImportValidationError.duplicateExternalId
        }
        let validatedSelections = try selections.map { try $0.validated() }
        return ImportDocument(schemaVersion: schemaVersion, events: validatedEvents, selections: validatedSelections)
    }
}

public enum ImportValidationError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case duplicateExternalId

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            AppLocalization.format(
                "error.unsupported_schema_version",
                defaultValue: "不支持 schemaVersion %lld，当前仅支持 1。",
                Int64(version)
            )
        case .duplicateExternalId:
            AppLocalization.text(
                "error.duplicate_external_id",
                defaultValue: "同一导入文件中不能出现重复的 externalId。"
            )
        }
    }
}

public struct CalendarSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String
    public let sourceIdentifier: String
    public let type: String
    public let colorHex: String
    public let allowsContentModifications: Bool

    public init(
        id: String,
        title: String,
        sourceTitle: String,
        sourceIdentifier: String,
        type: String,
        colorHex: String,
        allowsContentModifications: Bool
    ) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.sourceIdentifier = sourceIdentifier
        self.type = type
        self.colorHex = colorHex
        self.allowsContentModifications = allowsContentModifications
    }
}

public struct CountdownEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Stable across the occurrences of one recurring event series.
    /// Non-recurring events leave this nil so same-title one-off events remain distinct.
    public let seriesIdentifier: String?
    public let calendarItemIdentifier: String?
    public let externalIdentifier: String?
    public let title: String
    public let eventDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let calendarIdentifier: String
    public let sourceTitle: String
    public let colorHex: String
    public let notes: String?
    public let url: String?

    public init(
        id: String,
        seriesIdentifier: String? = nil,
        calendarItemIdentifier: String?,
        externalIdentifier: String?,
        title: String,
        eventDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        calendarIdentifier: String,
        sourceTitle: String,
        colorHex: String,
        notes: String?,
        url: String?
    ) {
        self.id = id
        self.seriesIdentifier = seriesIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.eventDate = eventDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.calendarIdentifier = calendarIdentifier
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
        self.notes = notes
        self.url = url
    }
}

public enum SelectionMode: String, Codable, CaseIterable, Sendable {
    case exactEvent
    case annualTitle
    case managedRecord
}

public struct SelectionDraft: Codable, Equatable, Sendable {
    public var calendarTitle: String
    public var eventTitle: String
    public var mode: SelectionMode

    public init(calendarTitle: String, eventTitle: String, mode: SelectionMode = .annualTitle) {
        self.calendarTitle = calendarTitle
        self.eventTitle = eventTitle
        self.mode = mode
    }

    public func validated() throws -> SelectionDraft {
        let calendar = calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !calendar.isEmpty, !event.isEmpty else {
            throw ManagedEventValidationError.invalidSelection
        }
        return SelectionDraft(calendarTitle: calendar, eventTitle: event, mode: mode)
    }
}

public struct CountdownSelection: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var mode: SelectionMode
    public var calendarIdentifier: String?
    public var calendarTitle: String
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var managedRecordID: UUID?
    public var eventTitle: String
    public var occurrenceDate: Date?
    public let selectedAt: Date

    public init(
        id: UUID = UUID(),
        mode: SelectionMode,
        calendarIdentifier: String? = nil,
        calendarTitle: String,
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        managedRecordID: UUID? = nil,
        eventTitle: String,
        occurrenceDate: Date? = nil,
        selectedAt: Date = Date()
    ) {
        self.id = id
        self.mode = mode
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.managedRecordID = managedRecordID
        self.eventTitle = eventTitle
        self.occurrenceDate = occurrenceDate
        self.selectedAt = selectedAt
    }

    public func matches(_ event: CountdownEvent, calendar: Calendar = .current) -> Bool {
        let sameCalendar = calendarIdentifier == event.calendarIdentifier || (
            calendarIdentifier == nil && calendarTitle == event.calendarTitle
        )
        guard sameCalendar else { return false }

        switch mode {
        case .exactEvent:
            if let eventIdentifier, eventIdentifier == event.calendarItemIdentifier { return true }
            if let externalIdentifier, externalIdentifier == event.externalIdentifier,
               let occurrenceDate {
                return calendar.isDate(occurrenceDate, inSameDayAs: event.eventDate)
            }
            return false
        case .annualTitle:
            return eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                == event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        case .managedRecord:
            guard let managedRecordID,
                  let url = event.url,
                  let parsed = URL(string: url) else { return false }
            return parsed.scheme == ProductConstants.managedURLScheme
                && parsed.host == ProductConstants.managedURLHost
                && parsed.pathComponents.dropFirst().first?.lowercased() == managedRecordID.uuidString.lowercased()
        }
    }
}

public struct CountdownDisplayPreferences: Codable, Equatable, Sendable {
    public var untrackedCalendarIdentifiers: Set<String>
    public var pinnedSelectionID: UUID?

    public init(
        untrackedCalendarIdentifiers: Set<String> = [],
        pinnedSelectionID: UUID? = nil
    ) {
        self.untrackedCalendarIdentifiers = untrackedCalendarIdentifiers
        self.pinnedSelectionID = pinnedSelectionID
    }

    private enum CodingKeys: String, CodingKey {
        case untrackedCalendarIdentifiers
        case pinnedSelectionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        untrackedCalendarIdentifiers = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .untrackedCalendarIdentifiers
        ) ?? []
        pinnedSelectionID = try container.decodeIfPresent(UUID.self, forKey: .pinnedSelectionID)
    }

    public func isCalendarTracked(_ calendarIdentifier: String) -> Bool {
        !untrackedCalendarIdentifiers.contains(calendarIdentifier)
    }

    public func visibleSelectedEvents(
        from events: [CountdownEvent],
        selections: [CountdownSelection]
    ) -> [CountdownEvent] {
        CountdownSelectionStore.nextSelectedEvents(from: events, selections: selections)
            .filter { isCalendarTracked($0.calendarIdentifier) }
    }

    public func featuredEvent(
        from visibleEvents: [CountdownEvent],
        selections: [CountdownSelection]
    ) -> CountdownEvent? {
        if let pinnedSelectionID,
           let pinnedSelection = selections.first(where: { $0.id == pinnedSelectionID }),
           let pinnedEvent = visibleEvents.first(where: { pinnedSelection.matches($0) }) {
            return pinnedEvent
        }
        return visibleEvents.first
    }
}
