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
        switch kind {
        case .countdown:
            addCountdownItems(to: menu)
        case .mission:
            addMissionItems(to: menu)
        case .todayTasks:
            addTodayTaskItems(to: menu)
        }
        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "打开知行", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func addCountdownItems(to menu: NSMenu) {
        let events = model.selectedEvents
            .sorted { $0.eventDate < $1.eventDate }
            .prefix(5)
        guard !events.isEmpty else {
            menu.addItem(disabledItem("尚无追踪倒数日"))
            return
        }
        for event in events {
            let item = NSMenuItem(
                title: "\(event.title)  ·  \(CountdownCalculator.label(until: event.eventDate))",
                action: #selector(openCountdown),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = DateSupport.dateOnlyString(event.eventDate)
            menu.addItem(item)
        }
    }

    private func addMissionItems(to menu: NSMenu) {
        guard let selectedID = overview.selectedMissionID,
              let result = workspace.missions.first(where: { $0.mission.id == selectedID && $0.mission.deletedAt == nil }) else {
            menu.addItem(disabledItem("尚未选择使命"))
            return
        }
        menu.addItem(disabledItem(result.mission.title))
        let progress = result.progress.displayPercent.map { String(format: "成果进度 %.0f%%", $0) } ?? "尚未规划"
        menu.addItem(disabledItem(progress))
        if let summary = result.mission.markdownDescription?
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            menu.addItem(disabledItem(summary))
        }
    }

    private func addTodayTaskItems(to menu: NSMenu) {
        let tasks = workspace.todayTasks.filter { $0.occurrence.status == .open }
        guard !tasks.isEmpty else {
            menu.addItem(disabledItem("今天没有待办任务"))
            return
        }
        for task in tasks {
            let item = NSMenuItem(title: task.title, action: #selector(completeTodayTask(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = task.occurrence.id
            item.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "完成任务")
            menu.addItem(item)
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        item.toolTip = title
        return item
    }

    private func update(_ kind: StatusBarOverviewKind) {
        guard let button = items[kind]?.button else { return }
        items[kind]?.menu = menu(for: kind)
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

    @objc private func openMainWindow() {
        onOpen(.countdown)
    }

    @objc private func completeTodayTask(_ sender: NSMenuItem) {
        guard let occurrenceID = sender.representedObject as? UUID,
              let task = workspace.todayTasks.first(where: { $0.occurrence.id == occurrenceID && $0.occurrence.status == .open }) else {
            return
        }
        workspace.complete(task)
        refresh()
    }
}
#endif
