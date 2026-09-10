#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    let openAppearanceSettings: () -> Void
    @State private var section: AppSection = .countdown

    var body: some View {
        NavigationSplitView {
            AppSectionSidebar(
                selection: $section,
                countdownCount: model.selectedEvents.count,
                taskCount: workspace.openTasks.count,
                missionCount: workspace.missions.count,
                habitCount: workspace.habits.count
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
        } detail: {
            switch section {
            case .countdown:
                MainView(model: model, openAppearanceSettings: openAppearanceSettings)
            case .tasks:
                TaskListView(workspace: workspace)
            case .missions:
                MissionListView(workspace: workspace)
            case .habits:
                HabitListView(workspace: workspace)
            }
        }
        .onAppear { try? workspace.reload() }
        .onOpenURL { url in
            guard let route = AppRoute.parse(url) else { return }
            switch route {
            case .open, .section(.countdown), .countdownEvent, .permissionSettings, .syncStatus:
                section = .countdown
            case .section(.tasks), .task:
                section = .tasks
            case .section(.missions), .mission:
                section = .missions
            case .section(.habits), .habit:
                section = .habits
            }
        }
    }
}
