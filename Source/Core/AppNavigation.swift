import Foundation

public enum AppSection: String, CaseIterable, Hashable, Identifiable, Sendable {
    case countdown
    case tasks
    case missions
    case habits

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .countdown:
            AppLocalization.text("nav.countdown", defaultValue: "倒数日")
        case .tasks:
            AppLocalization.text("nav.tasks", defaultValue: "任务清单")
        case .missions:
            AppLocalization.text("nav.missions", defaultValue: "使命清单")
        case .habits:
            AppLocalization.text("nav.habits", defaultValue: "打卡")
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

    public var accessibilityIdentifier: String {
        "tab-\(rawValue)"
    }
}

public enum AppRoute: Hashable, Sendable {
    case section(AppSection)
    case task(UUID)
    case mission(UUID)
    case habit(UUID)
    case countdown(UUID)
    case calendar(String)
    case syncStatus
    case permissionSettings

    public var section: AppSection {
        switch self {
        case let .section(section):
            section
        case .task:
            .tasks
        case .mission:
            .missions
        case .habit:
            .habits
        case .countdown, .calendar:
            .countdown
        case .syncStatus, .permissionSettings:
            .countdown
        }
    }

    public static func parse(url: URL) -> AppRoute? {
        if let link = DomainLink.parse(url) {
            switch link.kind {
            case .task:
                return .task(link.id)
            case .mission:
                return .mission(link.id)
            case .habit:
                return .habit(link.id)
            case .event:
                return .countdown(link.id)
            }
        }
        guard url.scheme == ProductConstants.managedURLScheme else { return nil }
        switch url.host {
        case "countdown":
            return .section(.countdown)
        case "tasks":
            return .section(.tasks)
        case "missions":
            return .section(.missions)
        case "habits":
            return .section(.habits)
        case "sync":
            return .syncStatus
        case "settings", "permissions":
            return .permissionSettings
        default:
            return nil
        }
    }
}
