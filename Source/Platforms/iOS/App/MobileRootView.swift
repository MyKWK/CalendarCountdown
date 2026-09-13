import CalendarCountdownCore
import SwiftUI

struct MobileRootView: View {
    @ObservedObject var session: MobileAppSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                PadSplitRoot(session: session)
            } else {
                PhoneTabRoot(session: session)
            }
        }
        .tint(Color("AccentColor"))
        .zhixingForeground(.body)
        .sheet(isPresented: $session.showingSettings) {
            NavigationStack {
                MobileSettingsView(session: session)
            }
        }
        .sheet(isPresented: $session.showingSyncStatus) {
            NavigationStack {
                MobileSyncStatusView(session: session)
            }
        }
        .sheet(isPresented: $session.showingAddEvent) {
            AddEventView(calendars: session.model.writableCalendars) { draft in
                await session.model.add(draft)
            }
        }
        .sheet(isPresented: $session.showingAddTask) {
            AddTaskSheet(missions: session.workspace.missions.map(\.mission)) { command in
                session.workspace.createTask(command)
            }
        }
        .sheet(isPresented: $session.showingAddMission) {
            AddMissionSheet(initialColor: session.workspace.suggestedMissionColor.rawValue) { command in
                session.workspace.createMission(command)
            }
        }
        .sheet(isPresented: $session.showingAddHabit) {
            AddHabitSheet { command in
                session.workspace.createHabit(command)
            }
        }
    }
}
