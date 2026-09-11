import CalendarCountdownCalendar
import CalendarCountdownCore
import CalendarCountdownPersistence
import SwiftUI

@main
struct CalendarCountdownMobileApp: App {
    @StateObject private var session = MobileAppSession()

    init() {
        DiagnosticLogger.shared.configure(component: "mobile")
        DiagnosticLogger.shared.log(.notice, category: .lifecycle, event: "mobile.app.started")
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView(session: session)
                .onAppear { session.bootstrap() }
                .onOpenURL { session.open($0) }
        }
    }
}
