import CalendarCountdownCore
import EventKit
import Foundation

public struct ReminderRepository: @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func authorizationState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
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
        try await store.requestFullAccessToReminders()
    }

    public func lists() throws -> [CalendarSummary] {
        try requireFullAccess()
        return store.calendars(for: .reminder).map { calendar in
            CalendarSummary(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: calendar.source.title,
                sourceIdentifier: calendar.source.sourceIdentifier,
                type: "reminder",
                colorHex: "#5B8DEF",
                allowsContentModifications: calendar.allowsContentModifications
            )
        }
    }

    public func nativeItems() async throws -> [ProjectedNativeItem] {
        try requireFullAccess()
        return try await fetchSnapshots().compactMap { snapshot in
            guard let url = snapshot.url, DomainLink.parse(url) != nil else { return nil }
            return ProjectedNativeItem(
                url: url,
                kind: .reminder,
                appleIdentifier: snapshot.identifier,
                title: snapshot.title,
                completed: snapshot.completed,
                due: snapshot.due
            )
        }
    }

    public func apply(_ desired: DesiredProjection, into calendar: EKCalendar? = nil) async throws -> String {
        try requireFullAccess()
        guard desired.projectionKind == .reminder else {
            throw DomainError.validation("ReminderRepository 只处理 reminder 投影。")
        }
        let target = try writableCalendar(calendar)
        let snapshots = try await fetchSnapshots()
        let existingID = snapshots.first(where: { $0.url == desired.url })?.identifier
        let reminder = existingID.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
            ?? EKReminder(eventStore: store)
        reminder.calendar = target
        reminder.title = desired.title
        reminder.notes = desired.notes
        reminder.url = URL(string: desired.url)
        reminder.priority = desired.priority.eventKitPriority
        reminder.isCompleted = desired.completed
        if let due = desired.due {
            reminder.dueDateComponents = Calendar.current.dateComponents(in: TimeZone.current, from: due)
        } else {
            reminder.dueDateComponents = nil
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    public func remove(url: String) async throws {
        try requireFullAccess()
        let snapshots = try await fetchSnapshots()
        for snapshot in snapshots where snapshot.url == url {
            if let reminder = store.calendarItem(withIdentifier: snapshot.identifier) as? EKReminder {
                try store.remove(reminder, commit: true)
            }
        }
    }

    public func ensureTaskList() throws -> EKCalendar {
        try requireFullAccess()
        let title = "CalendarCountdown 任务"
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == title && $0.allowsContentModifications }) {
            return existing
        }
        if let def = store.defaultCalendarForNewReminders(), def.allowsContentModifications {
            return def
        }
        return try writableCalendar(nil)
    }

    private struct ReminderSnapshot: Sendable {
        var identifier: String
        var title: String
        var url: String?
        var completed: Bool
        var due: Date?
    }

    private func fetchSnapshots() async throws -> [ReminderSnapshot] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { items in
                let snapshots = (items ?? []).map { reminder in
                    ReminderSnapshot(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title,
                        url: reminder.url?.absoluteString,
                        completed: reminder.isCompleted,
                        due: reminder.dueDateComponents?.date
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
    }

    private func writableCalendar(_ preferred: EKCalendar?) throws -> EKCalendar {
        if let preferred {
            guard preferred.allowsContentModifications else {
                throw EventKitRepositoryError.calendarReadOnly(preferred.title)
            }
            return preferred
        }
        if let def = store.defaultCalendarForNewReminders(), def.allowsContentModifications {
            return def
        }
        if let first = store.calendars(for: .reminder).first(where: \.allowsContentModifications) {
            return first
        }
        throw EventKitRepositoryError.calendarNotFound(identifier: nil, title: "Reminders")
    }

    private func requireFullAccess() throws {
        let state = authorizationState()
        guard state == .fullAccess else {
            throw DomainError(
                code: .remindersAccessRequired,
                message: "需要提醒事项完全访问权限，当前状态：\(state.rawValue)。"
            )
        }
    }
}
