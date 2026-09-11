import CalendarCountdownCore
import EventKit
import Foundation

public struct CalendarProjectionRepository: @unchecked Sendable {
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

    public func nativeItems(days: Int = 400) throws -> [ProjectedNativeItem] {
        try requireFullAccess()
        let start = Date().addingTimeInterval(-86_400 * 30)
        let end = Date().addingTimeInterval(86_400 * Double(days))
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard let url = event.url?.absoluteString,
                  let link = DomainLink.parse(url),
                  link.isSystemProjection else {
                return nil
            }
            return ProjectedNativeItem(
                url: url,
                kind: .event,
                appleIdentifier: event.calendarItemIdentifier,
                title: event.title,
                completed: false,
                due: event.endDate
            )
        }
    }

    public func apply(_ desired: DesiredProjection, into calendar: EKCalendar? = nil) throws -> String {
        try requireFullAccess()
        guard desired.projectionKind == .event else {
            throw DomainError.validation("CalendarProjectionRepository 只处理 event 投影。")
        }
        let target = try writableCalendar(calendar)
        let existing = try find(url: desired.url)
        let event = existing ?? EKEvent(eventStore: store)
        event.calendar = target
        event.title = desired.title
        event.notes = desired.notes
        event.url = URL(string: desired.url)
        event.startDate = desired.start ?? desired.due ?? Date()
        event.endDate = desired.due ?? event.startDate.addingTimeInterval(3_600)
        event.isAllDay = desired.isAllDay
        try store.save(event, span: .thisEvent, commit: true)
        return event.calendarItemIdentifier
    }

    public func remove(url: String) throws {
        try requireFullAccess()
        if let event = try find(url: url) {
            try store.remove(event, span: .thisEvent, commit: true)
        }
    }

    private func find(url: String) throws -> EKEvent? {
        let items = try nativeItems()
        guard let identifier = items.first(where: { $0.url == url })?.appleIdentifier else { return nil }
        return store.calendarItem(withIdentifier: identifier) as? EKEvent
    }

    private func writableCalendar(_ preferred: EKCalendar?) throws -> EKCalendar {
        if let preferred {
            guard preferred.allowsContentModifications else {
                throw EventKitRepositoryError.calendarReadOnly(preferred.title)
            }
            return preferred
        }
        let title = "CalendarCountdown 使命"
        if let named = store.calendars(for: .event).first(where: { $0.title == title && $0.allowsContentModifications }) {
            return named
        }
        if let def = store.defaultCalendarForNewEvents, def.allowsContentModifications {
            return def
        }
        if let first = store.calendars(for: .event).first(where: \.allowsContentModifications) {
            return first
        }
        throw EventKitRepositoryError.calendarNotFound(identifier: nil, title: "Calendar")
    }

    private func requireFullAccess() throws {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw DomainError(
                code: .calendarAccessRequired,
                message: "需要日历完全访问权限，当前状态：\(state.rawValue)。"
            )
        }
    }
}

public struct AppleProjectionRuntime: ProjectionApplying {
    private let reminders: ReminderRepository
    private let events: CalendarProjectionRepository

    public init(
        reminders: ReminderRepository = ReminderRepository(),
        events: CalendarProjectionRepository = CalendarProjectionRepository()
    ) {
        self.reminders = reminders
        self.events = events
    }

    public func nativeItems() async throws -> [ProjectedNativeItem] {
        var items: [ProjectedNativeItem] = []
        if reminders.authorizationState() == .fullAccess {
            items.append(contentsOf: try await reminders.nativeItems())
        }
        if events.authorizationState() == .fullAccess {
            items.append(contentsOf: try events.nativeItems())
        }
        return items
    }

    public func apply(_ desired: DesiredProjection) async throws -> String {
        switch desired.projectionKind {
        case .reminder:
            return try await reminders.apply(desired)
        case .event:
            return try events.apply(desired)
        case .reminderList:
            return desired.url
        }
    }

    public func remove(url: String, kind: ProjectionKind) async throws {
        switch kind {
        case .reminder:
            try await reminders.remove(url: url)
        case .event:
            try events.remove(url: url)
        case .reminderList:
            break
        }
    }

    public func accessStates() -> (reminders: CalendarAccessState, events: CalendarAccessState) {
        (reminders.authorizationState(), events.authorizationState())
    }
}
