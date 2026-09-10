import Foundation

public enum AppSection: String, CaseIterable, Hashable, Codable, Sendable {
    case countdown
    case tasks
    case missions
    case habits

    public var title: String {
        switch self {
        case .countdown:
            AppLocalization.text("navigation.countdown_days", defaultValue: "倒数日")
        case .tasks:
            AppLocalization.text("navigation.task_list", defaultValue: "任务清单")
        case .missions:
            AppLocalization.text("navigation.mission_list", defaultValue: "使命清单")
        case .habits:
            AppLocalization.text("navigation.habits", defaultValue: "打卡")
        }
    }

    public var systemImage: String {
        switch self {
        case .countdown: "calendar.badge.clock"
        case .tasks: "checklist"
        case .missions: "flag.fill"
        case .habits: "flame.fill"
        }
    }
}

public enum AppRoute: Hashable, Sendable {
    case section(AppSection)
    case countdownEvent(UUID)
    case task(UUID)
    case mission(UUID)
    case habit(UUID)
    case open
    case syncStatus
    case permissionSettings

    public static func parse(_ url: URL) -> AppRoute? {
        guard url.scheme == ProductConstants.managedURLScheme else { return nil }
        let host = url.host ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "", "open":
            return .open
        case "event":
            guard let id = parts.first.flatMap(UUID.init(uuidString:)) else { return .section(.countdown) }
            return .countdownEvent(id)
        case "task":
            guard let id = parts.first.flatMap(UUID.init(uuidString:)) else { return .section(.tasks) }
            return .task(id)
        case "mission":
            guard let id = parts.first.flatMap(UUID.init(uuidString:)) else { return .section(.missions) }
            return .mission(id)
        case "habit":
            guard let id = parts.first.flatMap(UUID.init(uuidString:)) else { return .section(.habits) }
            return .habit(id)
        case "sync":
            return .syncStatus
        case "settings":
            return .permissionSettings
        default:
            return .open
        }
    }
}
