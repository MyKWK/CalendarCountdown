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
        displayPreferences = CountdownDisplayPreferencesStore.load()
        trackedEventsDocument = (try? TrackedEventsFileStore.load()) ?? .empty
    }

    var writableCalendars: [CalendarSummary] {
        calendars.filter(\.allowsContentModifications)
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        accessState = await repository.authorizationState()
        if accessState == .fullAccess { await refresh() }
    }

    func requestAccess() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await repository.requestFullAccess()
            accessState = await repository.authorizationState()
            if accessState == .fullAccess { await refresh() }
        } catch {
            errorMessage = error.localizedDescription
            accessState = await repository.authorizationState()
        }
    }

    func refresh() async {
        guard accessState == .fullAccess else { return }
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
        } catch {
            errorMessage = error.localizedDescription
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
            try CountdownDisplayPreferencesStore.save(updated)
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
            try CountdownDisplayPreferencesStore.save(updated)
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
                try CountdownDisplayPreferencesStore.save(updated)
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
        do {
            let result = try await repository.writeCalendarBacked(draft)
            statusMessage = AppLocalization.format(
                "status.calendar_sync_complete",
                defaultValue: "已同步到 Apple 日历，生成 %lld 个事件",
                Int64(result.createdEventCount)
            )
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importDocument(at url: URL, dryRun: Bool = false) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try JSONCoding.decoder().decode(ImportDocument.self, from: Data(contentsOf: url))
            let result = try await repository.importDocument(document, dryRun: dryRun)
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
    }
}
