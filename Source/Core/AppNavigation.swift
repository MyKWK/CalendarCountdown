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

    public var subtitle: String {
        switch self {
        case .countdown:
            AppLocalization.text("nav.countdown.subtitle", defaultValue: "关注最近要到来的日子")
        case .tasks:
            AppLocalization.text("nav.tasks.subtitle", defaultValue: "完成当下最重要的事")
        case .missions:
            AppLocalization.text("nav.missions.subtitle", defaultValue: "推进有边界的长期结果")
        case .habits:
            AppLocalization.text("nav.habits.subtitle", defaultValue: "用连续性保持节奏")
        }
    }

    public var createActionTitle: String {
        switch self {
        case .countdown:
            AppLocalization.text("action.create_countdown", defaultValue: "新建倒数")
        case .tasks:
            AppLocalization.text("action.create_task", defaultValue: "新建任务")
        case .missions:
            AppLocalization.text("action.create_mission", defaultValue: "新建使命")
        case .habits:
            AppLocalization.text("action.create_habit", defaultValue: "新建打卡")
        }
    }

    public var createHelp: String {
        switch self {
        case .countdown:
            AppLocalization.text("help.create_countdown", defaultValue: "新建倒数日（⇧⌘D）")
        case .tasks:
            AppLocalization.text("help.create_task", defaultValue: "新建任务（⇧⌘N）")
        case .missions:
            AppLocalization.text("help.create_mission", defaultValue: "新建使命（⇧⌘M）")
        case .habits:
            AppLocalization.text("help.create_habit", defaultValue: "新建打卡（⇧⌘H）")
        }
    }

    public var emptySymbol: String {
        switch self {
        case .countdown: "calendar"
        case .tasks: "checkmark.circle"
        case .missions: "flag"
        case .habits: "flame"
        }
    }

    public var emptyDescription: String {
        switch self {
        case .countdown:
            AppLocalization.text(
                "empty.select_event_description",
                defaultValue: "从任意 Apple 日历中选择具体事件加入倒数。"
            )
        case .tasks:
            AppLocalization.text("empty.tasks_description", defaultValue: "没有符合条件的任务。")
        case .missions:
            AppLocalization.text(
                "empty.missions_description",
                defaultValue: "创建一个有边界、最终可以完成的长期结果。"
            )
        case .habits:
            AppLocalization.text(
                "empty.habits_description",
                defaultValue: "习惯关注一致性，而不是最终做完。"
            )
        }
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
