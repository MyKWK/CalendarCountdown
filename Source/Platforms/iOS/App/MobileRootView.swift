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
    }
}
