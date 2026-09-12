import CalendarCountdownCore
import SwiftUI

struct CalendarAccessActions: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let action = CalendarAccessRecovery.action(for: model.accessState)
        VStack(spacing: 8) {
            if action != .none {
                Button(buttonTitle(for: action)) {
                    Task { await model.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading)
                .accessibilityIdentifier(accessIdentifier)
                .appActionFocusEffectDisabled()
            }
            if action == .openSystemSettings {
                Text(
                    AppLocalization.text(
                        "calendar.access.recover_help",
                        defaultValue: "在系统设置中打开日历权限后，回到知行即可继续读取倒数。"
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var accessIdentifier: String {
        #if os(iOS)
        "mobile-request-calendar"
        #else
        "calendar-access-action"
        #endif
    }

    private func buttonTitle(for action: CalendarAccessAction) -> String {
        switch action {
        case .openSystemSettings:
            AppLocalization.text("calendar.access.open_settings", defaultValue: "在系统设置中打开")
        case .requestPrompt, .none:
            AppLocalization.text("calendar.access.authorize", defaultValue: "授权日历访问")
        }
    }
}
