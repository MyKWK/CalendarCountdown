import CalendarCountdownCalendar
import CalendarCountdownCore
import CalendarCountdownPersistence
import Combine
import Foundation

@MainActor
final class MobileAppSession: ObservableObject {
    @Published var section: AppSection = .countdown
    @Published var showingSettings = false
    @Published var showingSyncStatus = false
    @Published var route: AppRoute?

    let model: AppModel
    let workspace: WorkspaceModel

    init(workspace: Workspace? = nil, model: AppModel = AppModel()) {
        self.model = model
        if let workspace {
            self.workspace = WorkspaceModel(workspace: workspace)
        } else {
            self.workspace = WorkspaceModel()
        }
    }

    func bootstrap() {
        workspace.reload()
        Task { await model.bootstrap() }
    }

    func refresh() {
        workspace.reload()
        Task { await model.refresh() }
        Task { await workspace.reconcileProjections() }
    }

    func open(_ url: URL) {
        guard let parsed = AppRoute.parse(url: url) else { return }
        route = parsed
        switch parsed {
        case .syncStatus:
            showingSyncStatus = true
        case .permissionSettings:
            showingSettings = true
        default:
            section = parsed.section
        }
    }
}
