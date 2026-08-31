import AppKit
import CalendarCountdownCore
import EventKit
import Foundation

public enum CalendarAccessState: String, Codable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
    case unknown
}

public enum EventKitRepositoryError: LocalizedError {
    case calendarAccessRequired(CalendarAccessState)
    case calendarNotFound(identifier: String?, title: String?)
    case ambiguousCalendarTitle(String, [String])
    case calendarReadOnly(String)
    case invalidManagedURL
    case recordNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case let .calendarAccessRequired(state):
            AppLocalization.format(
                "error.calendar_access_required",
                defaultValue: "需要 Apple 日历完全访问权限，当前状态：%@。",
                state.rawValue
            )
        case let .calendarNotFound(identifier, title):
            AppLocalization.format(
                "error.calendar_not_found",
                defaultValue: "找不到目标 Apple 日历（identifier: %@, title: %@）。",
                identifier ?? AppLocalization.text("common.not_provided", defaultValue: "未提供"),
                title ?? AppLocalization.text("common.not_provided", defaultValue: "未提供")
            )
        case let .ambiguousCalendarTitle(title, sources):
            AppLocalization.format(
                "error.ambiguous_calendar_title",
                defaultValue: "存在多个名为“%@”的日历，请使用 calendarIdentifier 指定。来源：%@。",
                title,
                ListFormatter.localizedString(byJoining: sources)
            )
        case let .calendarReadOnly(title):
            AppLocalization.format(
                "error.calendar_read_only",
                defaultValue: "Apple 日历“%@”是只读的，不能写入。",
                title
            )
        case .invalidManagedURL:
            AppLocalization.text(
                "error.invalid_managed_url",
                defaultValue: "无法生成本工具事件的稳定 URL。"
            )
        case let .recordNotFound(id):
            AppLocalization.format(
                "error.record_not_found",
                defaultValue: "找不到本工具记录：%@。",
                id.uuidString
            )
        }
    }
}

public struct ManagedEventWriteResult: Codable, Sendable {
    public let record: ManagedEventRecord
    public let createdEventCount: Int
    public let wasCreated: Bool
    public let selectedForCountdown: Bool
}

public struct CalendarEventWriteResult: Codable, Sendable {
    public let createdEventCount: Int
    public let selectedForCountdown: Bool
}

public struct ImportRunResult: Codable, Sendable {
    public let dryRun: Bool
    public let validatedEventCount: Int
    public let validatedSelectionCount: Int
    public let createdOrUpdatedRecordIDs: [UUID]
    public let projectedEventCount: Int
    public let selectionCount: Int
}

public actor EventKitRepository {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func authorizationState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess, .authorized: .fullAccess
        @unknown default: .unknown
        }
    }

    @discardableResult
    public func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func calendars() throws -> [CalendarSummary] {
        try requireFullAccess()
        return store.calendars(for: .event).map(calendarSummary).sorted { lhs, rhs in
            if lhs.sourceTitle == rhs.sourceTitle {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.sourceTitle.localizedStandardCompare(rhs.sourceTitle) == .orderedAscending
        }
    }

    public func events(
        from startDate: Date = Date(),
        days: Int = ProductConstants.defaultFetchDays,
        calendarIdentifiers: [String] = []
    ) throws -> [CountdownEvent] {
        try requireFullAccess()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let boundedDays = max(1, min(days, 3_653))
        let end = calendar.date(byAdding: .day, value: boundedDays, to: start)
            ?? start.addingTimeInterval(Double(boundedDays) * 86_400)
        let requestedCalendars = calendarIdentifiers.isEmpty
            ? nil
            : store.calendars(for: .event).filter { calendarIdentifiers.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: requestedCalendars)

        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map(countdownEvent)
            .sorted { lhs, rhs in
                if lhs.eventDate == rhs.eventDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.eventDate < rhs.eventDate
            }
    }

    public func selectedUpcomingEvents(
        from startDate: Date = Date(),
        days: Int = ProductConstants.defaultFetchDays
    ) throws -> [CountdownEvent] {
        let all = try events(from: startDate, days: days)
        let selections = try CountdownSelectionStore.load()
        return CountdownSelectionStore.nextSelectedEvents(from: all, selections: selections)
    }

    @discardableResult
    public func select(event: CountdownEvent, mode: SelectionMode) throws -> CountdownSelection {
        let selection = CountdownSelection(
            mode: mode,
            calendarIdentifier: event.calendarIdentifier,
            calendarTitle: event.calendarTitle,
            eventIdentifier: event.calendarItemIdentifier,
            externalIdentifier: event.externalIdentifier,
            eventTitle: event.title,
            occurrenceDate: event.eventDate
        )
        try CountdownSelectionStore.upsert(selection)
        _ = try synchronizeTrackedEventsDocument()
        return selection
    }

    @discardableResult
    public func select(
        draft: SelectionDraft,
        synchronizeTrackingDocument: Bool = true
    ) throws -> CountdownSelection {
        let draft = try draft.validated()
        let matchingCalendars = store.calendars(for: .event).filter { $0.title == draft.calendarTitle }
        let calendarIdentifier: String?
        if matchingCalendars.count == 1 {
            calendarIdentifier = matchingCalendars[0].calendarIdentifier
        } else {
            calendarIdentifier = nil
        }
        let selection = CountdownSelection(
            mode: draft.mode,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: draft.calendarTitle,
            eventTitle: draft.eventTitle
        )
        try CountdownSelectionStore.upsert(selection)
        if synchronizeTrackingDocument {
            _ = try synchronizeTrackedEventsDocument()
        }
        return selection
    }

    public func selections() throws -> [CountdownSelection] {
        try CountdownSelectionStore.load()
    }

    public func removeSelection(id: UUID) throws {
        try CountdownSelectionStore.remove(id: id)
        _ = try synchronizeTrackedEventsDocument()
    }

    @discardableResult
    public func synchronizeTrackedEventsDocument(
        now: Date = Date()
    ) throws -> TrackedEventsDocument {
        try requireFullAccess()
        let selections = try CountdownSelectionStore.load()
        let preferences = CountdownDisplayPreferencesStore.load()
        let visibleEvents = preferences.visibleSelectedEvents(
            from: try events(from: now),
            selections: selections
        )
        return try saveTrackedEventsDocument(
            visibleEvents: visibleEvents,
            selections: selections,
            pinnedSelectionID: preferences.pinnedSelectionID,
            now: now
        )
    }

    @discardableResult
    public func saveTrackedEventsDocument(
        visibleEvents: [CountdownEvent],
        selections: [CountdownSelection],
        pinnedSelectionID: UUID?,
        now: Date = Date()
    ) throws -> TrackedEventsDocument {
        try requireFullAccess()
        let managedRecords: [UUID: ManagedEventRecord] = Dictionary(
            uniqueKeysWithValues: try ManagedEventFileStore.load().map { ($0.id, $0) }
        )
        let trackedEvents: [TrackedEventRecord] = visibleEvents.compactMap { event -> TrackedEventRecord? in
            let matchingSelections = selections.filter { $0.matches(event) }
            guard let selection = matchingSelections.first(where: { $0.id == pinnedSelectionID })
                ?? matchingSelections.first else {
                return nil
            }
            let managedRecord = selection.managedRecordID.flatMap { managedRecords[$0] }
            return trackedEventRecord(
                event: event,
                selection: selection,
                managedRecord: managedRecord,
                isPinned: selection.id == pinnedSelectionID
            )
        }
        let document = TrackedEventsDocument(
            updatedAt: now,
            events: trackedEvents.sorted { lhs, rhs in
                if lhs.nextOccurrence == rhs.nextOccurrence {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return (lhs.nextOccurrence ?? "9999-12-31") < (rhs.nextOccurrence ?? "9999-12-31")
            }
        )
        try TrackedEventsFileStore.save(document)
        return document
    }

    public func write(
        _ draft: ManagedEventDraft,
        synchronizeTrackingDocument: Bool = true
    ) throws -> ManagedEventWriteResult {
        try requireFullAccess()
        let validated = try draft.validated()
        let destination = try writableCalendar(
            identifier: validated.calendarIdentifier,
            title: validated.calendarTitle
        )
        let upserted = try ManagedEventFileStore.upsert(validated)

        if !upserted.wasCreated {
            try removeProjectedEvents(recordID: upserted.record.id, commit: true)
        }
        let count = try project(record: upserted.record, to: destination)

        if validated.selectForCountdown {
            let selection = CountdownSelection(
                mode: .managedRecord,
                calendarIdentifier: destination.calendarIdentifier,
                calendarTitle: destination.title,
                managedRecordID: upserted.record.id,
                eventTitle: validated.title
            )
            try CountdownSelectionStore.upsert(selection)
        }

        if synchronizeTrackingDocument {
            _ = try synchronizeTrackedEventsDocument()
        }

        return ManagedEventWriteResult(
            record: upserted.record,
            createdEventCount: count,
            wasCreated: upserted.wasCreated,
            selectedForCountdown: validated.selectForCountdown
        )
    }

    /// Writes a user-entered event directly to Apple Calendar. Event content and
    /// recurrence details remain calendar-backed; no ManagedEventRecord is created.
    public func writeCalendarBacked(_ draft: ManagedEventDraft) throws -> CalendarEventWriteResult {
        try requireFullAccess()
        let validated = try draft.validated()
        let destination = try writableCalendar(
            identifier: validated.calendarIdentifier,
            title: validated.calendarTitle
        )
        let groupID = UUID()
        var createdEvents: [EKEvent] = []

        switch validated.calendarSystem {
        case .gregorian:
            guard let value = validated.date,
                  let date = DateSupport.parseDateOnly(value),
                  let start = DateSupport.applying(time: validated.time, to: date) else {
                throw ManagedEventValidationError.invalidGregorianDate(validated.date)
            }
            let event = makeCalendarBackedEvent(
                draft: validated,
                startDate: start,
                calendar: destination,
                url: calendarBackedURL(groupID: groupID, draft: validated)
            )
            if validated.recurrence == .yearly {
                event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil))
            }
            try store.save(event, span: .thisEvent, commit: true)
            createdEvents = [event]

        case .lunar:
            guard let month = validated.lunarMonth, let day = validated.lunarDay else {
                throw ManagedEventValidationError.invalidLunarDay(validated.lunarDay)
            }
            let currentYear = Calendar.current.component(.year, from: Date())
            let today = Calendar.current.startOfDay(for: Date())
            for year in currentYear...(currentYear + ProductConstants.defaultProjectionYears) {
                let dates = LunarDateResolver.dates(
                    month: month,
                    day: day,
                    leapMonthPolicy: validated.lunarLeapMonthPolicy,
                    invalidDayPolicy: validated.invalidLunarDayPolicy,
                    inGregorianYear: year
                )
                for (index, date) in dates.enumerated() where date >= today {
                    let event = makeCalendarBackedEvent(
                        draft: validated,
                        startDate: date,
                        calendar: destination,
                        url: calendarBackedURL(
                            groupID: groupID,
                            draft: validated,
                            year: year,
                            occurrenceIndex: index
                        )
                    )
                    try store.save(event, span: .thisEvent, commit: false)
                    createdEvents.append(event)
                }
            }
            if !createdEvents.isEmpty { try store.commit() }
        }

        if validated.selectForCountdown {
            let selection = CountdownSelection(
                mode: .managedRecord,
                calendarIdentifier: destination.calendarIdentifier,
                calendarTitle: destination.title,
                managedRecordID: groupID,
                eventTitle: validated.title
            )
            try CountdownSelectionStore.upsert(selection)
        }

        _ = try synchronizeTrackedEventsDocument()

        return CalendarEventWriteResult(
            createdEventCount: createdEvents.count,
            selectedForCountdown: validated.selectForCountdown
        )
    }

    public func importDocument(_ document: ImportDocument, dryRun: Bool) throws -> ImportRunResult {
        try requireFullAccess()
        let validated = try document.validated()
        for draft in validated.events {
            _ = try writableCalendar(identifier: draft.calendarIdentifier, title: draft.calendarTitle)
        }

        if dryRun {
            return ImportRunResult(
                dryRun: true,
                validatedEventCount: validated.events.count,
                validatedSelectionCount: validated.selections.count,
                createdOrUpdatedRecordIDs: [],
                projectedEventCount: 0,
                selectionCount: 0
            )
        }

        var ids: [UUID] = []
        var projectedCount = 0
        for draft in validated.events {
            let result = try write(draft, synchronizeTrackingDocument: false)
            ids.append(result.record.id)
            projectedCount += result.createdEventCount
        }
        for selection in validated.selections {
            _ = try select(draft: selection, synchronizeTrackingDocument: false)
        }

        _ = try synchronizeTrackedEventsDocument()

        return ImportRunResult(
            dryRun: false,
            validatedEventCount: validated.events.count,
            validatedSelectionCount: validated.selections.count,
            createdOrUpdatedRecordIDs: ids,
            projectedEventCount: projectedCount,
            selectionCount: validated.selections.count + validated.events.filter(\.selectForCountdown).count
        )
    }

    public func syncManagedRecords() throws -> Int {
        try requireFullAccess()
        var projectedCount = 0
        for record in try ManagedEventFileStore.load() {
            let destination = try writableCalendar(
                identifier: record.draft.calendarIdentifier,
                title: record.draft.calendarTitle
            )
            projectedCount += try projectMissing(record: record, to: destination)
        }
        _ = try synchronizeTrackedEventsDocument()
        return projectedCount
    }

    public func managedRecords() throws -> [ManagedEventRecord] {
        try ManagedEventFileStore.load()
    }

    public func updateManagedRecord(id: UUID, draft: ManagedEventDraft) throws -> ManagedEventWriteResult {
        try requireFullAccess()
        guard try ManagedEventFileStore.record(id: id) != nil else {
            throw EventKitRepositoryError.recordNotFound(id)
        }
        let validated = try draft.validated()
        let destination = try writableCalendar(
            identifier: validated.calendarIdentifier,
            title: validated.calendarTitle
        )
        try removeProjectedEvents(recordID: id, commit: true)
        let record = try ManagedEventFileStore.replace(id: id, draft: validated)
        let count = try project(record: record, to: destination)

        var savedSelections = try CountdownSelectionStore.load()
        savedSelections.removeAll { $0.managedRecordID == id }
        if validated.selectForCountdown {
            savedSelections.append(CountdownSelection(
                mode: .managedRecord,
                calendarIdentifier: destination.calendarIdentifier,
                calendarTitle: destination.title,
                managedRecordID: id,
                eventTitle: validated.title
            ))
        }
        try CountdownSelectionStore.save(savedSelections)
        _ = try synchronizeTrackedEventsDocument()
        return ManagedEventWriteResult(
            record: record,
            createdEventCount: count,
            wasCreated: false,
            selectedForCountdown: validated.selectForCountdown
        )
    }

    public func deleteManagedRecord(id: UUID) throws {
        try requireFullAccess()
        guard try ManagedEventFileStore.record(id: id) != nil else {
            throw EventKitRepositoryError.recordNotFound(id)
        }
        try removeProjectedEvents(recordID: id, commit: true)
        _ = try ManagedEventFileStore.remove(id: id)
        var savedSelections = try CountdownSelectionStore.load()
        savedSelections.removeAll { $0.managedRecordID == id }
        try CountdownSelectionStore.save(savedSelections)
        _ = try synchronizeTrackedEventsDocument()
    }

    private func requireFullAccess() throws {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw EventKitRepositoryError.calendarAccessRequired(state)
        }
    }

    private func writableCalendar(identifier: String?, title: String?) throws -> EKCalendar {
        if let identifier, !identifier.isEmpty, let calendar = store.calendar(withIdentifier: identifier) {
            guard calendar.allowsContentModifications else {
                throw EventKitRepositoryError.calendarReadOnly(calendar.title)
            }
            return calendar
        }

        guard let title, !title.isEmpty else {
            throw EventKitRepositoryError.calendarNotFound(identifier: identifier, title: title)
        }
        let matches = store.calendars(for: .event).filter { $0.title == title }
        guard !matches.isEmpty else {
            throw EventKitRepositoryError.calendarNotFound(identifier: identifier, title: title)
        }
        guard matches.count == 1 else {
            throw EventKitRepositoryError.ambiguousCalendarTitle(title, matches.map { $0.source.title })
        }
        guard matches[0].allowsContentModifications else {
            throw EventKitRepositoryError.calendarReadOnly(title)
        }
        return matches[0]
    }

    private func makeCalendarBackedEvent(
        draft: ManagedEventDraft,
        startDate: Date,
        calendar: EKCalendar,
        url: URL?
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = startDate
        event.isAllDay = draft.isAllDay
        event.endDate = draft.isAllDay
            ? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86_400)
            : startDate.addingTimeInterval(3_600)
        event.notes = draft.notes
        event.url = url
        for days in draft.alertDaysBefore {
            event.addAlarm(EKAlarm(relativeOffset: -Double(days) * 86_400))
        }
        return event
    }

    private func calendarBackedURL(
        groupID: UUID,
        draft: ManagedEventDraft,
        year: Int? = nil,
        occurrenceIndex: Int? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = ProductConstants.managedURLScheme
        components.host = ProductConstants.managedURLHost
        components.path = "/\(groupID.uuidString.lowercased())"
        var queryItems = [
            URLQueryItem(name: "storage", value: "calendar"),
            URLQueryItem(name: "calendarSystem", value: draft.calendarSystem.rawValue),
            URLQueryItem(name: "recurrence", value: draft.recurrence.rawValue)
        ]
        if let startYear = draft.startYear {
            queryItems.append(URLQueryItem(name: "startYear", value: String(startYear)))
        }
        if let date = draft.date {
            queryItems.append(URLQueryItem(name: "date", value: date))
        }
        if let time = draft.time {
            queryItems.append(URLQueryItem(name: "time", value: time))
        }
        if let year { queryItems.append(URLQueryItem(name: "year", value: String(year))) }
        if let occurrenceIndex {
            queryItems.append(URLQueryItem(name: "occurrence", value: String(occurrenceIndex)))
        }
        if let lunarMonth = draft.lunarMonth {
            queryItems.append(URLQueryItem(name: "lunarMonth", value: String(lunarMonth)))
        }
        if let lunarDay = draft.lunarDay {
            queryItems.append(URLQueryItem(name: "lunarDay", value: String(lunarDay)))
        }
        if draft.calendarSystem == .lunar {
            queryItems.append(URLQueryItem(
                name: "lunarLeapMonthPolicy",
                value: draft.lunarLeapMonthPolicy.rawValue
            ))
            queryItems.append(URLQueryItem(
                name: "invalidLunarDayPolicy",
                value: draft.invalidLunarDayPolicy.rawValue
            ))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func project(record: ManagedEventRecord, to calendar: EKCalendar) throws -> Int {
        switch record.draft.calendarSystem {
        case .gregorian:
            return try projectGregorian(record: record, to: calendar)
        case .lunar:
            return try projectLunar(record: record, to: calendar, onlyMissing: false)
        }
    }

    private func projectMissing(record: ManagedEventRecord, to calendar: EKCalendar) throws -> Int {
        let existingURLs = try projectedURLs(recordID: record.id, calendar: calendar)
        switch record.draft.calendarSystem {
        case .gregorian:
            guard existingURLs.isEmpty else { return 0 }
            return try projectGregorian(record: record, to: calendar)
        case .lunar:
            return try projectLunar(record: record, to: calendar, onlyMissing: true, existingURLs: existingURLs)
        }
    }

    private func projectGregorian(record: ManagedEventRecord, to calendar: EKCalendar) throws -> Int {
        guard let value = record.draft.date,
              let date = DateSupport.parseDateOnly(value),
              let start = DateSupport.applying(time: record.draft.time, to: date) else {
            throw ManagedEventValidationError.invalidGregorianDate(record.draft.date)
        }
        let event = makeEvent(record: record, startDate: start, calendar: calendar, year: nil)
        if record.draft.recurrence == .yearly {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil))
        }
        try store.save(event, span: .thisEvent, commit: true)
        return 1
    }

    private func projectLunar(
        record: ManagedEventRecord,
        to calendar: EKCalendar,
        onlyMissing: Bool,
        existingURLs: Set<String> = []
    ) throws -> Int {
        guard let month = record.draft.lunarMonth, let day = record.draft.lunarDay else {
            throw ManagedEventValidationError.invalidLunarDay(record.draft.lunarDay)
        }
        let currentYear = Calendar.current.component(.year, from: Date())
        var count = 0
        let today = Calendar.current.startOfDay(for: Date())
        for year in currentYear...(currentYear + ProductConstants.defaultProjectionYears) {
            let dates = LunarDateResolver.dates(
                month: month,
                day: day,
                leapMonthPolicy: record.draft.lunarLeapMonthPolicy,
                invalidDayPolicy: record.draft.invalidLunarDayPolicy,
                inGregorianYear: year
            )
            for (index, date) in dates.enumerated() {
                if date < today { continue }
                guard let url = managedURL(recordID: record.id, year: year, occurrenceIndex: index) else {
                    throw EventKitRepositoryError.invalidManagedURL
                }
                if onlyMissing, existingURLs.contains(url.absoluteString) { continue }
                let event = makeEvent(record: record, startDate: date, calendar: calendar, year: year, url: url)
                try store.save(event, span: .thisEvent, commit: false)
                count += 1
            }
        }
        if count > 0 { try store.commit() }
        return count
    }

    private func makeEvent(
        record: ManagedEventRecord,
        startDate: Date,
        calendar: EKCalendar,
        year: Int?,
        url: URL? = nil
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = record.draft.title
        event.startDate = startDate
        event.isAllDay = record.draft.isAllDay
        event.endDate = record.draft.isAllDay
            ? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86_400)
            : startDate.addingTimeInterval(3_600)
        event.notes = record.draft.notes
        event.url = url ?? managedURL(recordID: record.id, year: year, occurrenceIndex: nil)
        for days in record.draft.alertDaysBefore {
            event.addAlarm(EKAlarm(relativeOffset: -Double(days) * 86_400))
        }
        return event
    }

    private func managedURL(recordID: UUID, year: Int?, occurrenceIndex: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = ProductConstants.managedURLScheme
        components.host = ProductConstants.managedURLHost
        components.path = "/\(recordID.uuidString.lowercased())"
        var queryItems: [URLQueryItem] = []
        if let year { queryItems.append(URLQueryItem(name: "year", value: String(year))) }
        if let occurrenceIndex { queryItems.append(URLQueryItem(name: "occurrence", value: String(occurrenceIndex))) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func projectedURLs(recordID: UUID, calendar: EKCalendar) throws -> Set<String> {
        let all = try projectedEvents(recordID: recordID, calendars: [calendar])
        return Set(all.compactMap { $0.url?.absoluteString })
    }

    private func projectedEvents(recordID: UUID, calendars: [EKCalendar]? = nil) throws -> [EKEvent] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let start = Calendar.current.date(from: DateComponents(year: currentYear - 1, month: 1, day: 1)) ?? Date()
        let end = Calendar.current.date(from: DateComponents(year: currentYear + ProductConstants.defaultProjectionYears + 1, month: 12, day: 31))
            ?? Date().addingTimeInterval(12 * 365 * 86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let expectedPath = "/\(recordID.uuidString.lowercased())"
        return store.events(matching: predicate).filter { event in
            guard let url = event.url else { return false }
            return url.scheme == ProductConstants.managedURLScheme
                && url.host == ProductConstants.managedURLHost
                && url.path.lowercased() == expectedPath
        }
    }

    private func removeProjectedEvents(recordID: UUID, commit: Bool) throws {
        let events = try projectedEvents(recordID: recordID)
        var removedRecurringSeries = Set<String>()
        for event in events {
            if event.hasRecurrenceRules {
                let identifier = event.calendarItemIdentifier
                guard removedRecurringSeries.insert(identifier).inserted else { continue }
                try store.remove(event, span: .futureEvents, commit: false)
            } else {
                try store.remove(event, span: .thisEvent, commit: false)
            }
        }
        if commit, !events.isEmpty { try store.commit() }
    }

    private func trackedEventRecord(
        event: CountdownEvent,
        selection: CountdownSelection,
        managedRecord: ManagedEventRecord?,
        isPinned: Bool
    ) -> TrackedEventRecord {
        let originalEvent = event.calendarItemIdentifier.flatMap {
            store.calendarItem(withIdentifier: $0) as? EKEvent
        }
        let metadata = managedMetadata(from: event.url)
        let draft = managedRecord?.draft
        let rule = originalEvent?.recurrenceRules?.first
        let calendarSystem = draft?.calendarSystem
            ?? metadata["calendarSystem"].flatMap(CalendarSystemKind.init(rawValue:))
            ?? rule.map { recurrenceCalendarSystem(for: $0.calendarIdentifier) }
            ?? .gregorian
        let frequency = trackedFrequency(
            selectionMode: selection.mode,
            draft: draft,
            metadata: metadata,
            recurrenceRule: rule
        )
        let lunarLeapMonthPolicy = draft?.lunarLeapMonthPolicy
            ?? metadata["lunarLeapMonthPolicy"].flatMap(LunarLeapMonthPolicy.init(rawValue:))
        let invalidLunarDayPolicy = draft?.invalidLunarDayPolicy
            ?? metadata["invalidLunarDayPolicy"].flatMap(InvalidLunarDayPolicy.init(rawValue:))

        let originalStartDate = draft?.date.flatMap { DateSupport.parseDateOnly($0) }
            ?? metadata["date"].flatMap { DateSupport.parseDateOnly($0) }
            ?? originalEvent?.startDate
            ?? event.eventDate
        let gregorianYear = Calendar.current.component(.year, from: originalStartDate)
        let startYear = draft?.startYear
            ?? draft?.date.flatMap { Int($0.prefix(4)) }
            ?? metadata["startYear"].flatMap(Int.init)
            ?? metadata["date"].flatMap { Int($0.prefix(4)) }
            ?? gregorianYear

        let month: Int
        let day: Int
        let isLeapMonth: Bool?
        switch calendarSystem {
        case .gregorian:
            let components = Calendar.current.dateComponents([.month, .day], from: originalStartDate)
            month = components.month ?? 1
            day = components.day ?? 1
            isLeapMonth = nil
        case .lunar:
            var lunarCalendar = Calendar(identifier: .chinese)
            lunarCalendar.timeZone = originalEvent?.timeZone ?? .current
            let components = lunarCalendar.dateComponents([.month, .day], from: originalStartDate)
            month = draft?.lunarMonth
                ?? metadata["lunarMonth"].flatMap(Int.init)
                ?? components.month
                ?? 1
            day = draft?.lunarDay
                ?? metadata["lunarDay"].flatMap(Int.init)
                ?? components.day
                ?? 1
            isLeapMonth = lunarLeapMonthValue(draft: draft, metadata: metadata, components: components)
        }

        let time = draft?.time
            ?? metadata["time"]
            ?? (event.isAllDay ? nil : timeString(originalStartDate))
        let kind = trackedEventKind(event: event, originalEvent: originalEvent, frequency: frequency)
        return TrackedEventRecord(
            id: selection.id,
            title: event.title,
            kind: kind,
            date: TrackedDateDefinition(
                startYear: startYear,
                calendarSystem: calendarSystem,
                month: month,
                day: day,
                isLeapMonth: isLeapMonth
            ),
            recurrence: TrackedRecurrenceDefinition(
                frequency: frequency,
                calendarSystem: calendarSystem,
                lunarLeapMonthPolicy: calendarSystem == .lunar ? lunarLeapMonthPolicy : nil,
                invalidLunarDayPolicy: calendarSystem == .lunar ? invalidLunarDayPolicy : nil
            ),
            nextOccurrence: DateSupport.dateOnlyString(event.eventDate),
            time: time,
            timeZoneIdentifier: originalEvent?.timeZone?.identifier ?? TimeZone.current.identifier,
            isAllDay: event.isAllDay,
            calendar: TrackedCalendarReference(
                identifier: event.calendarIdentifier,
                title: event.calendarTitle,
                sourceTitle: event.sourceTitle,
                colorHex: event.colorHex
            ),
            tracking: TrackedSelectionReference(
                mode: selection.mode,
                trackedSince: selection.selectedAt,
                isPinned: isPinned
            ),
            appleCalendar: TrackedAppleCalendarReference(
                calendarItemIdentifier: event.calendarItemIdentifier,
                externalIdentifier: event.externalIdentifier,
                managedRecordID: selection.managedRecordID
            )
        )
    }

    private func managedMetadata(from value: String?) -> [String: String] {
        guard let value,
              let components = URLComponents(string: value),
              components.scheme == ProductConstants.managedURLScheme,
              components.host == ProductConstants.managedURLHost else {
            return [:]
        }
        var metadata: [String: String] = [:]
        for item in components.queryItems ?? [] where metadata[item.name] == nil {
            metadata[item.name] = item.value
        }
        return metadata
    }

    private func recurrenceCalendarSystem(for recurrenceCalendarIdentifier: String) -> CalendarSystemKind {
        let normalized = recurrenceCalendarIdentifier.lowercased()
        return normalized.contains("chinese") || normalized.contains("lunar") ? .lunar : .gregorian
    }

    private func trackedFrequency(
        selectionMode: SelectionMode,
        draft: ManagedEventDraft?,
        metadata: [String: String],
        recurrenceRule: EKRecurrenceRule?
    ) -> TrackedRecurrenceFrequency {
        switch selectionMode {
        case .exactEvent:
            return .none
        case .annualTitle:
            return .yearly
        case .managedRecord:
            if let recurrence = draft?.recurrence
                ?? metadata["recurrence"].flatMap(RecurrenceKind.init(rawValue:)) {
                return recurrence == .yearly ? .yearly : .none
            }
            guard let recurrenceRule else { return .none }
            return switch recurrenceRule.frequency {
            case .daily: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            @unknown default: .unknown
            }
        }
    }

    private func lunarLeapMonthValue(
        draft: ManagedEventDraft?,
        metadata: [String: String],
        components: DateComponents
    ) -> Bool? {
        let policy = draft?.lunarLeapMonthPolicy
            ?? metadata["lunarLeapMonthPolicy"].flatMap(LunarLeapMonthPolicy.init(rawValue:))
        return switch policy {
        case .regularOnly: false
        case .leapOnly: true
        case .both: nil
        case nil: components.isLeapMonth
        }
    }

    private func timeString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func trackedEventKind(
        event: CountdownEvent,
        originalEvent: EKEvent?,
        frequency: TrackedRecurrenceFrequency
    ) -> TrackedEventKind {
        let calendarName = event.calendarTitle.lowercased()
        let title = event.title.lowercased()
        if originalEvent?.birthdayContactIdentifier != nil
            || calendarName.contains("生日")
            || calendarName.contains("birthday") {
            return .birthday
        }
        if title.contains("纪念") || title.contains("anniversary") {
            return .anniversary
        }
        if frequency == .none { return .importantDate }
        return .other
    }

    private func calendarSummary(_ calendar: EKCalendar) -> CalendarSummary {
        CalendarSummary(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceTitle: calendar.source.title,
            sourceIdentifier: calendar.source.sourceIdentifier,
            type: calendarTypeName(calendar.type),
            colorHex: colorHex(calendar.color),
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private func countdownEvent(_ event: EKEvent) -> CountdownEvent {
        let occurrenceDate = event.occurrenceDate ?? event.startDate ?? .distantFuture
        let stableID = [
            event.calendar.calendarIdentifier,
            event.eventIdentifier ?? event.calendarItemIdentifier,
            String(Int(occurrenceDate.timeIntervalSince1970))
        ].joined(separator: ":")
        return CountdownEvent(
            id: stableID,
            seriesIdentifier: seriesIdentifier(for: event),
            calendarItemIdentifier: event.calendarItemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            title: event.title ?? AppLocalization.text(
                "event.untitled",
                defaultValue: "未命名事件"
            ),
            eventDate: event.startDate ?? .distantFuture,
            endDate: event.endDate ?? event.startDate ?? .distantFuture,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            calendarIdentifier: event.calendar.calendarIdentifier,
            sourceTitle: event.calendar.source.title,
            colorHex: colorHex(event.calendar.color),
            notes: event.notes,
            url: event.url?.absoluteString
        )
    }

    private func seriesIdentifier(for event: EKEvent) -> String? {
        if let url = event.url,
           url.scheme == ProductConstants.managedURLScheme,
           url.host == ProductConstants.managedURLHost,
           let groupID = url.pathComponents.dropFirst().first,
           !groupID.isEmpty {
            return "calendarcountdown:\(event.calendar.calendarIdentifier):\(groupID.lowercased())"
        }

        guard event.hasRecurrenceRules || event.occurrenceDate != nil else { return nil }
        let eventKitIdentifier = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        return "eventkit:\(event.calendar.calendarIdentifier):\(eventKitIdentifier)"
    }

    private func colorHex(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return "#8E8E93" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }

    private func calendarTypeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: "local"
        case .calDAV: "calDAV"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }
}
