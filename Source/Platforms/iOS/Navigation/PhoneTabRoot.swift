import CalendarCountdownCore
import SwiftUI

private enum TaskInboxFilter: String, CaseIterable, Identifiable {
    case today
    case all
    case inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "今天"
        case .all:
            "全部"
        case .inbox:
            "收集箱"
        }
    }
}

struct PhoneTabRoot: View {
    @ObservedObject var session: MobileAppSession
    @State private var countdownPath = NavigationPath()
    @State private var tasksPath = NavigationPath()
    @State private var missionsPath = NavigationPath()
    @State private var habitsPath = NavigationPath()
    @State private var taskFilter: TaskInboxFilter = .today

    var body: some View {
        TabView(selection: $session.section) {
            NavigationStack(path: $countdownPath) {
                CountdownModuleView(model: session.model, searchText: "", selectedCalendarID: nil)
                    .modifier(MobileModuleToolbar(session: session))
            }
            .tabItem {
                Label(AppSection.countdown.title, systemImage: AppSection.countdown.systemImage)
            }
            .tag(AppSection.countdown)
            .accessibilityIdentifier(AppSection.countdown.accessibilityIdentifier)

            NavigationStack(path: $tasksPath) {
                tasksRoot
                    .modifier(MobileModuleToolbar(session: session))
            }
            .tabItem {
                Label(AppSection.tasks.title, systemImage: AppSection.tasks.systemImage)
            }
            .tag(AppSection.tasks)
            .accessibilityIdentifier(AppSection.tasks.accessibilityIdentifier)

            NavigationStack(path: $missionsPath) {
                MissionListView(workspace: session.workspace, searchText: "")
                    .modifier(MobileModuleToolbar(session: session))
            }
            .tabItem {
                Label(AppSection.missions.title, systemImage: AppSection.missions.systemImage)
            }
            .tag(AppSection.missions)
            .accessibilityIdentifier(AppSection.missions.accessibilityIdentifier)

            NavigationStack(path: $habitsPath) {
                HabitListView(workspace: session.workspace, searchText: "")
                    .modifier(MobileModuleToolbar(session: session))
            }
            .tabItem {
                Label(AppSection.habits.title, systemImage: AppSection.habits.systemImage)
            }
            .tag(AppSection.habits)
            .accessibilityIdentifier(AppSection.habits.accessibilityIdentifier)
        }
        .accessibilityIdentifier("mobile-tab-view")
    }

    @ViewBuilder
    private var tasksRoot: some View {
        VStack(spacing: 0) {
            Picker("任务筛选", selection: $taskFilter) {
                ForEach(TaskInboxFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("task-inbox-filter")

            TaskListView(
                title: AppSection.tasks.title,
                views: taskViews,
                workspace: session.workspace
            )
        }
    }

    private var taskViews: [TaskOccurrenceView] {
        switch taskFilter {
        case .today:
            session.workspace.todayTasks
        case .all:
            session.workspace.taskViews
        case .inbox:
            session.workspace.inboxTasks
        }
    }
}

struct PadSplitRoot: View {
    @ObservedObject var session: MobileAppSession
    @State private var taskFilter: TaskInboxFilter = .all

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Button {
                            session.section = section
                        } label: {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .foregroundStyle(.primary)
                        .listRowBackground(
                            session.section == section ? Color.accentColor.opacity(0.12) : Color.clear
                        )
                        .accessibilityAddTraits(session.section == section ? .isSelected : [])
                        .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                }
                Section {
                    Button {
                        session.showingSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("mobile-settings")
                    Button {
                        session.showingSyncStatus = true
                    } label: {
                        Label("同步状态", systemImage: "icloud")
                    }
                    .accessibilityIdentifier("mobile-sync-status")
                }
            }
            .navigationTitle("知行")
            .accessibilityIdentifier("mobile-sidebar")
        } content: {
            contentColumn
                .modifier(MobileModuleToolbar(session: session))
        } detail: {
            ContentUnavailableView(
                "选择一项",
                systemImage: "sidebar.squares.right",
                description: Text("从中间列表打开任务、使命、习惯或倒数详情。")
            )
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch session.section {
        case .countdown:
            CountdownModuleView(model: session.model, searchText: "", selectedCalendarID: nil)
        case .tasks:
            VStack(spacing: 0) {
                Picker("任务筛选", selection: $taskFilter) {
                    ForEach(TaskInboxFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)
                TaskListView(
                    title: AppSection.tasks.title,
                    views: padTaskViews,
                    workspace: session.workspace
                )
            }
        case .missions:
            MissionListView(workspace: session.workspace, searchText: "")
        case .habits:
            HabitListView(workspace: session.workspace, searchText: "")
        }
    }

    private var padTaskViews: [TaskOccurrenceView] {
        switch taskFilter {
        case .today:
            session.workspace.todayTasks
        case .all:
            session.workspace.taskViews
        case .inbox:
            session.workspace.inboxTasks
        }
    }
}

private struct MobileModuleToolbar: ViewModifier {
    @ObservedObject var session: MobileAppSession

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        switch session.section {
                        case .missions:
                            session.showingAddMission = true
                        case .habits:
                            session.showingAddHabit = true
                        case .countdown:
                            session.showingAddEvent = true
                        case .tasks:
                            session.showingAddTask = true
                        }
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .accessibilityIdentifier("mobile-add")
                    Button {
                        session.refresh()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("mobile-refresh")
                    Button {
                        session.showingSyncStatus = true
                    } label: {
                        Label("同步", systemImage: "icloud")
                    }
                    .accessibilityIdentifier("mobile-sync-status")
                    Button {
                        session.showingSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("mobile-settings")
                }
            }
    }
}
