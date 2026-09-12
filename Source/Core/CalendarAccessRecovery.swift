import Foundation

public enum CalendarAccessState: String, Codable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
    case unknown
}

public enum CalendarAccessAction: Equatable, Sendable {
    case none
    case requestPrompt
    case openSystemSettings
}

public enum CalendarAccessTransition: Equatable, Sendable {
    case unchanged
    case gainedAccess
    case lostAccess
    case stillUnavailable
}

/// Pure policy for recovering calendar access after the user changes Privacy settings.
public enum CalendarAccessRecovery: Sendable {
    public static let macOSCalendarPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
    )!

    public static func action(for state: CalendarAccessState) -> CalendarAccessAction {
        switch state {
        case .fullAccess:
            .none
        case .denied, .restricted:
            .openSystemSettings
        case .notDetermined, .writeOnly, .unknown:
            .requestPrompt
        }
    }

    public static func transition(
        from previous: CalendarAccessState,
        to current: CalendarAccessState
    ) -> CalendarAccessTransition {
        if previous == current { return .unchanged }
        if current == .fullAccess { return .gainedAccess }
        if previous == .fullAccess { return .lostAccess }
        return .stillUnavailable
    }

    public static func shouldLoadCalendarData(_ state: CalendarAccessState) -> Bool {
        state == .fullAccess
    }
}
