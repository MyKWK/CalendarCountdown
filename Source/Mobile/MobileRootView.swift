#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import SwiftUI

struct MobileRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    @Binding var pendingRoute: AppRoute?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: AppSection = .countdown
    @State private var selectedTaskID: UUID?
    @State private var selectedMissionID: UUID?
    @State private var selectedHabitID: UUID?

    var body: some View {
        Group {
            if sizeClass == .compact {
                phoneTabs
            } else {
                padSplit
            }
        }
        .onOpenURL { url in
            apply(route: AppRoute.parse(url))
        }
        .onChange(of: pendingRoute) { _, route in
            apply(route: route)
        }
        .onAppear { try? workspace.reload() }
    }

    private var phoneTabs: some View {
        TabView(selection: $section) {
            NavigationStack {
                countdownModule
            }
            .tabItem { Label(AppSection.countdown.title, systemImage: AppSection.countdown.systemImage) }
            .tag(AppSection.countdown)
            .accessibilityIdentifier("tab-countdown")

            NavigationStack {
                TaskListView(workspace: workspace, selectedID: $selectedTaskID)
                    .navigationDestination(item: $selectedTaskID) { id in
                        TaskDetailView(workspace: workspace, taskID: id)
                    }
            }
            .tabItem { Label(AppSection.tasks.title, systemImage: AppSection.tasks.systemImage) }
            .tag(AppSection.tasks)
            .accessibilityIdentifier("tab-tasks")

            NavigationStack {
                MissionListView(workspace: workspace, selectedID: $selectedMissionID)
                    .navigationDestination(item: $selectedMissionID) { id in
                        MissionDetailView(workspace: workspace, missionID: id)
                    }
            }
            .tabItem { Label(AppSection.missions.title, systemImage: AppSection.missions.systemImage) }
            .tag(AppSection.missions)
            .accessibilityIdentifier("tab-missions")

            NavigationStack {
                HabitListView(workspace: workspace, selectedID: $selectedHabitID)
                    .navigationDestination(item: $selectedHabitID) { id in
                        HabitDetailView(workspace: workspace, habitID: id)
                    }
            }
            .tabItem { Label(AppSection.habits.title, systemImage: AppSection.habits.systemImage) }
            .tag(AppSection.habits)
            .accessibilityIdentifier("tab-habits")
        }
    }

    private var padSplit: some View {
        NavigationSplitView {
            AppSectionSidebar(
                selection: $section,
                countdownCount: model.selectedEvents.count,
                taskCount: workspace.openTasks.count,
                missionCount: workspace.missions.count,
                habitCount: workspace.habits.count
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            switch section {
            case .countdown:
                countdownModule
            case .tasks:
                TaskListView(workspace: workspace, selectedID: $selectedTaskID)
            case .missions:
                MissionListView(workspace: workspace, selectedID: $selectedMissionID)
            case .habits:
                HabitListView(workspace: workspace, selectedID: $selectedHabitID)
            }
        } detail: {
            switch section {
            case .countdown:
                ContentUnavailableView("选择一个倒数事件", systemImage: AppSection.countdown.systemImage)
            case .tasks:
                if let selectedTaskID {
                    TaskDetailView(workspace: workspace, taskID: selectedTaskID)
                } else {
                    ContentUnavailableView("选择一个任务", systemImage: AppSection.tasks.systemImage)
                }
            case .missions:
                if let selectedMissionID {
                    MissionDetailView(workspace: workspace, missionID: selectedMissionID)
                } else {
                    ContentUnavailableView("选择一个使命", systemImage: AppSection.missions.systemImage)
                }
            case .habits:
                if let selectedHabitID {
                    HabitDetailView(workspace: workspace, habitID: selectedHabitID)
                } else {
                    ContentUnavailableView("选择一个习惯", systemImage: AppSection.habits.systemImage)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var countdownModule: some View {
        MainView(model: model, openAppearanceSettings: {})
    }

    private func apply(route: AppRoute?) {
        guard let route else { return }
        switch route {
        case .open, .section(.countdown), .countdownEvent, .permissionSettings, .syncStatus:
            section = .countdown
        case .section(.tasks):
            section = .tasks
        case let .task(id):
            section = .tasks
            selectedTaskID = id
        case .section(.missions):
            section = .missions
        case let .mission(id):
            section = .missions
            selectedMissionID = id
        case .section(.habits):
            section = .habits
        case let .habit(id):
            section = .habits
            selectedHabitID = id
        }
        pendingRoute = nil
    }
}
