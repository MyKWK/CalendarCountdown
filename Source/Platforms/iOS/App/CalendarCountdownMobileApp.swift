import CalendarCountdownCalendar
import CalendarCountdownCore
import CalendarCountdownPersistence
import SwiftUI

@main
struct CalendarCountdownMobileApp: App {
    @StateObject private var session = MobileAppSession()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        DiagnosticLogger.shared.configure(component: "mobile")
        DiagnosticLogger.shared.log(.notice, category: .lifecycle, event: "mobile.app.started")
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView(session: session)
                .onAppear { session.bootstrap() }
                .onOpenURL { session.open($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        session.refresh()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(session.section.createActionTitle) {
                    session.presentCreate()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
