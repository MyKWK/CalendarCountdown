#if os(macOS)
import AppKit
import CalendarCountdownCore
import Combine

@MainActor
final class StatusBarCoordinator: NSObject {
    private let overview: StatusBarOverviewSettings
    private let model: AppModel
    private let workspace: WorkspaceModel
    private let onOpen: (AppSection) -> Void
    private var items: [StatusBarOverviewKind: NSStatusItem] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    init(
        overview: StatusBarOverviewSettings,
        model: AppModel,
        workspace: WorkspaceModel,
        onOpen: @escaping (AppSection) -> Void
    ) {
        self.overview = overview
        self.model = model
        self.workspace = workspace
        self.onOpen = onOpen
        super.init()
    }

    func start() {
        guard !started else {
            refresh()
            return
        }
        started = true
        Publishers.CombineLatest4(
            overview.$showCountdown,
            overview.$showMissionProgress,
            overview.$showTodayTasks,
            overview.$selectedMissionID
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.refresh()
        }
        .store(in: &cancellables)
        Publishers.CombineLatest4(
            model.$featuredEvent,
            model.$accessState,
            workspace.$missions,
            workspace.$taskViews
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.refresh()
        }
        .store(in: &cancellables)
        refresh()
    }

    func stop() {
        cancellables.removeAll()
        destroyAll()
        started = false
    }

    func refresh() {
        overview.resolveSelectedMission(among: workspace.missions.map(\.mission))
        let desired = Set(overview.state.enabledKinds)
        let existingCounts = Dictionary(
            uniqueKeysWithValues: items.keys.map { ($0, 1) }
        )
        let plan = StatusBarItemRegistry.reconcile(desired: desired, existingCounts: existingCounts)
        for (kind, count) in plan.remove {
            if count > 0 {
                destroy(kind)
            }
        }
        for kind in plan.create where items[kind] == nil {
            items[kind] = makeItem(for: kind)
        }
        for kind in desired {
            update(kind)
        }
    }

    private func destroyAll() {
        for kind in Array(items.keys) {
            destroy(kind)
        }
    }

    private func destroy(_ kind: StatusBarOverviewKind) {
        guard let item = items.removeValue(forKey: kind) else { return }
        item.menu = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    private func makeItem(for kind: StatusBarOverviewKind) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.imageHugsTitle = true
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        item.menu = menu(for: kind)
        return item
    }

    private func menu(for kind: StatusBarOverviewKind) -> NSMenu {
        let menu = NSMenu()
        let title: String
        let selector: Selector
        switch kind {
        case .countdown:
            title = AppLocalization.text("status_bar.open_countdown", defaultValue: "打开倒数日")
            selector = #selector(openCountdown)
        case .mission:
            title = AppLocalization.text("status_bar.open_missions", defaultValue: "打开使命清单")
            selector = #selector(openMissions)
        case .todayTasks:
            title = AppLocalization.text("status_bar.open_tasks", defaultValue: "打开任务清单")
            selector = #selector(openTasks)
        }
        let openItem = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func update(_ kind: StatusBarOverviewKind) {
        guard let button = items[kind]?.button else { return }
        switch kind {
        case .countdown:
            button.image = StatusItemArtwork.countdownIcon
            button.image?.isTemplate = true
            if let event = model.featuredEvent {
                let days = CountdownCalculator.daysRemaining(until: event.eventDate)
                button.title = days == 0
                    ? AppLocalization.text("countdown.today", defaultValue: "今天")
                    : String(days)
                button.toolTip = AppLocalization.format(
                    "status_item.event_tooltip",
                    defaultValue: "%@ · %@ · %@",
                    event.title,
                    DateSupport.dateOnlyString(event.eventDate),
                    CountdownCalculator.label(until: event.eventDate)
                )
                button.setAccessibilityLabel(AppLocalization.format(
                    "status_item.accessibility_label",
                    defaultValue: "知行，%@，%@",
                    event.title,
                    CountdownCalculator.label(until: event.eventDate)
                ))
            } else {
                button.title = ""
                button.toolTip = AppLocalization.text(
                    "status_item.no_events",
                    defaultValue: "知行 · 尚无追踪事件"
                )
                button.setAccessibilityLabel(
                    AppLocalization.text("status_bar.countdown.empty", defaultValue: "倒数日，尚无追踪事件")
                )
            }

        case .mission:
            let selectedID = overview.selectedMissionID
            let result = workspace.missions.first(where: { $0.mission.id == selectedID && $0.mission.deletedAt == nil })
            let progress = result?.progress.progress
            button.image = StatusItemArtwork.missionProgress(progress: progress)
            button.image?.isTemplate = true
            let percent = StatusBarMissionPresentation.percentText(progress: progress)
            if let result {
                button.title = percent
                button.toolTip = AppLocalization.format(
                    "status_item.mission_tooltip",
                    defaultValue: "%@ · %@",
                    result.mission.title,
                    percent
                )
                button.setAccessibilityLabel(
                    AppLocalization.format(
                        "status_bar.mission.accessibility",
                        defaultValue: "使命 %@，进度 %@",
                        result.mission.title,
                        percent
                    )
                )
            } else {
                button.title = percent
                button.toolTip = AppLocalization.text(
                    "status_bar.mission.empty",
                    defaultValue: "尚未选择使命"
                )
                button.setAccessibilityLabel(
                    AppLocalization.text("status_bar.mission.empty", defaultValue: "尚未选择使命")
                )
            }

        case .todayTasks:
            let remaining = StatusBarTodaySemantics.remainingCount(views: workspace.taskViews)
            button.image = StatusItemArtwork.todayTasksIcon
            button.image?.isTemplate = true
            button.title = String(remaining)
            button.toolTip = AppLocalization.format(
                "status_bar.tasks.tooltip",
                defaultValue: "今日剩余 %lld 项未完成任务",
                Int64(remaining)
            )
            button.setAccessibilityLabel(
                AppLocalization.format(
                    "status_bar.tasks.accessibility",
                    defaultValue: "今日任务，剩余 %lld 项",
                    Int64(remaining)
                )
            )
        }
    }

    @objc private func openCountdown() {
        onOpen(.countdown)
    }

    @objc private func openMissions() {
        onOpen(.missions)
    }

    @objc private func openTasks() {
        onOpen(.tasks)
    }
}
#endif
