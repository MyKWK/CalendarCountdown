#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
#if canImport(CalendarCountdownPersistence)
import CalendarCountdownPersistence
#endif
import SwiftUI

@main
struct CalendarCountdowniOSApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var workspace: WorkspaceModel
    @StateObject private var sessionHolder: SessionHolder

    init() {
        let broker = (try? AppBroker.openShared(session: CloudProfileSession()))
            ?? (try! AppBroker.temporary(session: CloudProfileSession()))
        _workspace = StateObject(wrappedValue: WorkspaceModel(database: broker.database))
        _sessionHolder = StateObject(wrappedValue: SessionHolder(broker: broker))
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView(
                model: model,
                workspace: workspace,
                pendingRoute: $sessionHolder.pendingRoute
            )
            .task {
                model.countdownMirror = { [workspace] selections, preferences in
                    selections.forEach { workspace.mirrorCountdownSelection($0) }
                    workspace.mirrorCountdownPreferences(preferences)
                }
                await model.bootstrap()
                try? workspace.reload()
                try? await sessionHolder.broker.syncEngine.syncNow()
            }
            .onOpenURL { url in
                sessionHolder.pendingRoute = AppRoute.parse(url)
            }
        }
    }
}

@MainActor
final class SessionHolder: ObservableObject {
    let broker: AppBroker
    @Published var pendingRoute: AppRoute?

    init(broker: AppBroker) {
        self.broker = broker
    }
}
