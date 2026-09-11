import CalendarCountdownCalendar
import CalendarCountdownCore
import Combine
import Foundation
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accessState: CalendarAccessState = .notDetermined
    @Published private(set) var calendars: [CalendarSummary] = []
    @Published private(set) var events: [CountdownEvent] = []
    @Published private(set) var selections: [CountdownSelection] = []
    @Published private(set) var selectedEvents: [CountdownEvent] = []
    @Published private(set) var featuredEvent: CountdownEvent?
    @Published private(set) var displayPreferences: CountdownDisplayPreferences
    @Published private(set) var trackedEventsDocument: TrackedEventsDocument
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    let repository: EventKitRepository
    private var didBootstrap = false

    init(repository: EventKitRepository = EventKitRepository()) {
        self.repository = repository
        displayPreferences = .init()
        trackedEventsDocument = (try? TrackedEventsFileStore.load()) ?? .empty
    }

    var writableCalendars: [CalendarSummary] {
        calendars.filter(\.allowsContentModifications)
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        displayPreferences = (try? await repository.displayPreferences()) ?? .init()
        accessState = await repository.authorizationState()
        DiagnosticLogger.shared.log(
            .info,
            category: .calendar,
            event: "calendar.bootstrap.completed",
            metadata: ["access_state": accessState.rawValue]
        )
        if accessState == .fullAccess {
            await reconcileManagedCountdowns()
            await refresh()
        }
    }

    func requestAccess() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await repository.requestFullAccess()
            accessState = await repository.authorizationState()
            DiagnosticLogger.shared.log(
                .notice,
                category: .calendar,
                event: "calendar.access.updated",
                metadata: ["access_state": accessState.rawValue]
            )
            if accessState == .fullAccess {
                await reconcileManagedCountdowns()
                await refresh()
            }
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .calendar,
                event: "calendar.access.failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            errorMessage = error.localizedDescription
            accessState = await repository.authorizationState()
        }
    }

    func refresh() async {
        guard accessState == .fullAccess else { return }
        let operationID = UUID()
        let started = Date()
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedCalendars = repository.calendars()
            async let fetchedEvents = repository.events()
            async let fetchedSelections = repository.selections()
            let (calendarValues, eventValues, selectionValues) = try await (
                fetchedCalendars,
                fetchedEvents,
                fetchedSelections
            )
            calendars = calendarValues
            events = eventValues
            selections = selectionValues
            try await rebuildCountdownPresentation()
            DiagnosticLogger.shared.log(
                .notice,
                category: .calendar,
                event: "calendar.refresh.completed",
                correlationID: operationID,
                metadata: [
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                    "calendar_count": String(calendars.count),
                    "event_count": String(events.count),
                    "selection_count": String(selections.count),
                    "visible_count": String(selectedEvents.count)
                ]
            )
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .calendar,
                event: "calendar.refresh.failed",
                correlationID: operationID,
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000))
                ]) { current, _ in current }
            )
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileManagedCountdowns() async {
        do {
            let repairedCount = try await repository.syncManagedRecords()
            guard repairedCount > 0 else { return }
            DiagnosticLogger.shared.log(
                .notice,
                category: .calendar,
                event: "calendar.managed_countdowns.reconciled",
                metadata: ["projected_count": String(repairedCount)]
            )
        } catch {
            // A projection repair must not prevent the user from seeing calendar
            // data that EventKit can still read.
            DiagnosticLogger.shared.log(
                .error,
                category: .calendar,
                event: "calendar.managed_countdowns.reconcile_failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
        }
    }

    func isSelected(_ event: CountdownEvent) -> Bool {
        selections.contains { $0.matches(event) }
    }

    func isPinned(_ event: CountdownEvent) -> Bool {
        guard let pinnedSelectionID = displayPreferences.pinnedSelectionID,
              let selection = selections.first(where: { $0.id == pinnedSelectionID }) else {
            return false
        }
        return selection.matches(event)
    }

    func isCalendarTracked(_ calendarIdentifier: String) -> Bool {
        displayPreferences.isCalendarTracked(calendarIdentifier)
    }

    func setCalendarTracked(_ calendarIdentifier: String, tracked: Bool) async {
        var updated = displayPreferences
        if tracked {
            updated.untrackedCalendarIdentifiers.remove(calendarIdentifier)
        } else {
            updated.untrackedCalendarIdentifiers.insert(calendarIdentifier)
        }

        do {
            try await repository.saveDisplayPreferences(updated)
            displayPreferences = updated
            try await rebuildCountdownPresentation()
            statusMessage = tracked
                ? AppLocalization.text("status.calendar_tracked", defaultValue: "已追踪该类别")
                : AppLocalization.text("status.calendar_untracked", defaultValue: "该类别已设为不追踪")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePin(_ event: CountdownEvent) async {
        guard let matchingSelection = selections.first(where: { $0.matches(event) }) else {
            errorMessage = AppLocalization.text(
                "error.pin_requires_tracking",
                defaultValue: "请先将事件加入倒数，再进行置顶。"
            )
            return
        }

        var updated = displayPreferences
        updated.pinnedSelectionID = updated.pinnedSelectionID == matchingSelection.id
            ? nil
            : matchingSelection.id
        do {
            try await repository.saveDisplayPreferences(updated)
            displayPreferences = updated
            try await rebuildCountdownPresentation()
            statusMessage = updated.pinnedSelectionID == nil
                ? AppLocalization.text("status.unpinned", defaultValue: "已取消置顶")
                : AppLocalization.text("status.pinned", defaultValue: "已置顶到顶部菜单栏")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ event: CountdownEvent, mode: SelectionMode) async {
        do {
            _ = try await repository.select(event: event, mode: mode)
            statusMessage = mode == .annualTitle
                ? AppLocalization.text(
                    "status.annual_event_tracked",
                    defaultValue: "已按同名年度事件加入倒数"
                )
                : AppLocalization.text("status.event_tracked", defaultValue: "已加入倒数")
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unselect(_ event: CountdownEvent) async {
        let matching = selections.filter { $0.matches(event) }
        do {
            for selection in matching {
                try await repository.removeSelection(id: selection.id)
            }
            if matching.contains(where: { $0.id == displayPreferences.pinnedSelectionID }) {
                var updated = displayPreferences
                updated.pinnedSelectionID = nil
                try await repository.saveDisplayPreferences(updated)
                displayPreferences = updated
            }
            statusMessage = AppLocalization.text(
                "status.event_untracked",
                defaultValue: "已从倒数展示中移除"
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ draft: ManagedEventDraft) async -> Bool {
        let operationID = UUID()
        do {
            let result = try await repository.writeCalendarBacked(draft)
            DiagnosticLogger.shared.log(
                .notice,
                category: .calendar,
                event: "calendar.write.completed",
                correlationID: operationID,
                metadata: [
                    "created_events": String(result.createdEventCount),
                    "calendar_system": draft.calendarSystem.rawValue,
                    "recurrence": draft.recurrence.rawValue
                ]
            )
            statusMessage = AppLocalization.format(
                "status.calendar_sync_complete",
                defaultValue: "已同步到 Apple 日历，生成 %lld 个事件",
                Int64(result.createdEventCount)
            )
            await refresh()
            return true
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .calendar,
                event: "calendar.write.failed",
                correlationID: operationID,
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importDocument(at url: URL, dryRun: Bool = false) async {
        let operationID = UUID()
        let started = Date()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try JSONCoding.decoder().decode(ImportDocument.self, from: Data(contentsOf: url))
            let result = try await repository.importDocument(document, dryRun: dryRun)
            DiagnosticLogger.shared.log(
                .notice,
                category: .calendar,
                event: "calendar.import.completed",
                correlationID: operationID,
                metadata: [
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                    "dry_run": String(dryRun),
                    "validated_events": String(result.validatedEventCount),
                    "validated_selections": String(result.validatedSelectionCount),
                    "projected_events": String(result.projectedEventCount)
                ]
            )
            statusMessage = dryRun
                ? AppLocalization.format(
                    "status.import_validation_complete",
                    defaultValue: "校验通过：%lld 个待写事件，%lld 个已有事件选择",
                    Int64(result.validatedEventCount),
                    Int64(result.validatedSelectionCount)
                )
                : AppLocalization.format(
                    "status.import_complete",
                    defaultValue: "导入完成：生成 %lld 个日历事件",
                    Int64(result.projectedEventCount)
                )
            await refresh()
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .calendar,
                event: "calendar.import.failed",
                correlationID: operationID,
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "dry_run": String(dryRun),
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000))
                ]) { current, _ in current }
            )
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildCountdownPresentation() async throws {
        selectedEvents = displayPreferences.visibleSelectedEvents(
            from: events,
            selections: selections
        )
        featuredEvent = displayPreferences.featuredEvent(
            from: selectedEvents,
            selections: selections
        )
        trackedEventsDocument = try await repository.saveTrackedEventsDocument(
            visibleEvents: selectedEvents,
            selections: selections,
            pinnedSelectionID: displayPreferences.pinnedSelectionID
        )
        try WidgetSnapshotStore.save(events: selectedEvents)
        WidgetCenter.shared.reloadTimelines(ofKind: ProductConstants.widgetKind)
        DiagnosticLogger.shared.log(
            .debug,
            category: .widget,
            event: "widget.countdown_snapshot.saved",
            metadata: ["item_count": String(selectedEvents.count)]
        )
    }
}
