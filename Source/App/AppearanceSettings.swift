import AppKit
import CalendarCountdownCore
import Combine
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            AppLocalization.text("appearance.mode_system", defaultValue: "跟随系统")
        case .light:
            AppLocalization.text("appearance.mode_light", defaultValue: "浅色")
        case .dark:
            AppLocalization.text("appearance.mode_dark", defaultValue: "深色")
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppAppearanceSettings: ObservableObject {
    private enum Keys {
        static let mode = "appearance.mode"
        static let glassEnabled = WindowGlassAppearance.enabledDefaultsKey
        static let glassTransparency = WindowGlassAppearance.transparencyDefaultsKey
    }

    private let defaults: UserDefaults

    @Published var appearanceMode: AppAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.mode) }
    }

    @Published var windowGlassEnabled: Bool {
        didSet {
            if !WindowGlassAppearance.userFacingEnabled, windowGlassEnabled {
                windowGlassEnabled = false
                return
            }
            defaults.set(windowGlassEnabled, forKey: Keys.glassEnabled)
        }
    }

    @Published var windowGlassTransparency: Double {
        didSet {
            let clamped = WindowGlassAppearance.clamped(windowGlassTransparency)
            if clamped != windowGlassTransparency {
                windowGlassTransparency = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.glassTransparency)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearanceMode = AppAppearanceMode(
            rawValue: defaults.string(forKey: Keys.mode) ?? ""
        ) ?? .system

        WindowGlassAppearance.retireUserFacingPreference(in: defaults)
        windowGlassEnabled = false

        if defaults.object(forKey: Keys.glassTransparency) == nil {
            windowGlassTransparency = WindowGlassAppearance.defaultTransparency
        } else {
            windowGlassTransparency = WindowGlassAppearance.clamped(
                defaults.double(forKey: Keys.glassTransparency)
            )
        }
    }

    /// Fixed brand signal color. Mission identity colors are configured on each mission.
    var accentColor: Color { Color("AccentColor") }
}

enum AppSettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case statusBar
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance:
            AppLocalization.text("appearance.title", defaultValue: "外观")
        case .statusBar:
            AppLocalization.text("settings.status_bar.title", defaultValue: "菜单栏概览")
        case .shortcuts:
            "快捷键"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "circle.lefthalf.filled"
        case .statusBar: "menubar.rectangle"
        case .shortcuts: "command"
        }
    }

    var help: String {
        switch self {
        case .appearance: "设置浅色、深色与系统外观"
        case .statusBar: "选择显示在菜单栏中的概览"
        case .shortcuts: "查看并设置全局与当前界面快捷键"
        }
    }
}

@MainActor
final class AppSettingsNavigation: ObservableObject {
    @Published var selection: AppSettingsSection? = .appearance
}

struct AppSettingsView: View {
    @ObservedObject var settings: AppAppearanceSettings
    @ObservedObject var overview: StatusBarOverviewSettings
    @ObservedObject var shortcuts: AppShortcutCoordinator
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var navigation: AppSettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Section {
                    settingsRow(.appearance)
                } header: {
                    settingsSidebarHeader("个性化")
                }
                Section {
                    settingsRow(.statusBar)
                    settingsRow(.shortcuts)
                } header: {
                    settingsSidebarHeader("系统集成")
                }
            }
            .navigationTitle("设置")
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
        } detail: {
            switch navigation.selection ?? .appearance {
            case .appearance:
                AppearanceSettingsPane(settings: settings)
            case .statusBar:
                StatusBarOverviewPane(overview: overview, workspace: workspace)
            case .shortcuts:
                ShortcutSettingsPane(shortcuts: shortcuts)
            }
        }
        .frame(width: 760, height: 640)
        .zhixingForeground(.body)
        .tint(settings.accentColor)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private func settingsRow(_ section: AppSettingsSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .font(
                navigation.selection == section
                    ? ZhixingTypography.sidebarItemSelected
                    : ZhixingTypography.sidebarItem
            )
            .zhixingForeground(navigation.selection == section ? .heading : .body)
            .tag(section)
    }

    private func settingsSidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(ZhixingTypography.sidebarSectionTitle)
            .zhixingForeground(.supporting)
    }
}

private struct ShortcutSettingsPane: View {
    @ObservedObject var shortcuts: AppShortcutCoordinator

    var body: some View {
        Form {
            Section {
                Toggle("启用全局唤起", isOn: $shortcuts.globalWakeEnabled)

                ShortcutRow(
                    title: "打开主界面",
                    shortcut: AppShortcutCoordinator.globalWakeDisplay,
                    scope: "全局"
                )

                HStack(spacing: 7) {
                    Image(systemName: shortcuts.globalWakeStatus == .active
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(shortcuts.globalWakeStatus == .active ? .green : .orange)
                    Text(shortcuts.globalWakeStatus.title)
                        .font(.callout.weight(.medium))
                }
                Text(shortcuts.globalWakeStatus.detail)
                    .font(.callout)
                    .zhixingForeground(.supporting)
            } header: {
                settingsSectionHeader("全局快捷键")
            }

            Section {
                ShortcutRow(title: "新建倒数日", shortcut: "⌘⇧D", scope: "应用内")
                ShortcutRow(title: "新建任务", shortcut: "⌘⇧N", scope: "应用内")
                ShortcutRow(title: "新建使命", shortcut: "⌘⇧M", scope: "应用内")
                ShortcutRow(title: "新建打卡", shortcut: "⌘⇧H", scope: "应用内")
                ShortcutRow(title: "切换倒数日／任务／使命／打卡", shortcut: "⌘1–4", scope: "应用内")
            } header: {
                settingsSectionHeader("当前界面内")
            }

            Section {
                Text("全局快捷键仅在知行正在运行时生效；关闭主窗口不会退出应用，选择“退出知行”后则不会继续监听。应用内快捷键只会在知行位于前台时响应。")
                    .font(.callout)
                    .zhixingForeground(.supporting)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("快捷键")
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: String
    let scope: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(scope)
                .font(.caption)
                .zhixingForeground(.supporting)
            Text(shortcut)
                .font(.body.monospaced().weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSmall, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(scope)，\(shortcut)")
    }
}

private struct StatusBarOverviewPane: View {
    @ObservedObject var overview: StatusBarOverviewSettings
    @ObservedObject var workspace: WorkspaceModel

    private var liveMissions: [MissionDefinition] {
        workspace.missions.map(\.mission).filter { $0.deletedAt == nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    AppLocalization.text("settings.status_bar.countdown", defaultValue: "倒数日"),
                    isOn: $overview.showCountdown
                )
                Toggle(
                    AppLocalization.text("settings.status_bar.mission", defaultValue: "使命进度"),
                    isOn: $overview.showMissionProgress
                )
                Toggle(
                    AppLocalization.text("settings.status_bar.tasks", defaultValue: "今日任务"),
                    isOn: $overview.showTodayTasks
                )
            } footer: {
                Text(AppLocalization.text(
                    "settings.status_bar.help",
                    defaultValue: "三项可同时打开，各自占用一个独立菜单栏图标。关闭后该图标会移除。旧版本升级后默认只保留倒数日。"
                ))
                .font(.callout)
                .zhixingForeground(.supporting)
            }

            Section {
                if liveMissions.isEmpty {
                    Text(AppLocalization.text(
                        "settings.status_bar.mission_empty",
                        defaultValue: "还没有使命。新建一项使命后，就可以把它显示在菜单栏。"
                    ))
                    .zhixingForeground(.supporting)
                } else {
                    Picker(
                        AppLocalization.text("settings.status_bar.mission_picker", defaultValue: "显示的使命"),
                        selection: $overview.selectedMissionID
                    ) {
                        Text(AppLocalization.text("settings.status_bar.mission_none", defaultValue: "未选择"))
                            .tag(Optional<UUID>.none)
                        ForEach(liveMissions) { mission in
                            Text(mission.title).tag(Optional(mission.id))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppLocalization.text("settings.status_bar.title", defaultValue: "菜单栏概览"))
        .onAppear {
            overview.resolveSelectedMission(among: liveMissions)
        }
    }
}

private struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppAppearanceSettings

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: ZhixingMetrics.cornerSmall, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(settings.accentColor)
                            .frame(width: 18, height: 18)
                            .shadow(color: settings.accentColor.opacity(0.35), radius: 6)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalization.text("appearance.fixed_theme_name", defaultValue: "钛灰 · 冰川青"))
                            .font(ZhixingTypography.rowTitle)
                            .zhixingForeground(.heading)
                        Text(AppLocalization.text(
                            "appearance.fixed_theme_description",
                            defaultValue: "知行使用固定的冷灰界面与冰川青交互强调；颜色选择留给每一项使命。"
                        ))
                        .font(.callout)
                        .zhixingForeground(.supporting)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                settingsSectionHeader(
                    AppLocalization.text("appearance.design_language", defaultValue: "设计语言")
                )
            }

            Section {
                Picker("页面外观", selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(appearanceDescription)
                    .font(.callout)
                    .zhixingForeground(.supporting)
            } header: {
                settingsSectionHeader("页面外观")
            }

        }
        .formStyle(.grouped)
        .navigationTitle(AppLocalization.text("appearance.title", defaultValue: "外观"))
        .tint(settings.accentColor)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private var appearanceDescription: String {
        switch settings.appearanceMode {
        case .system:
            AppLocalization.text(
                "appearance.description_system",
                defaultValue: "根据 macOS 当前的浅色或深色外观自动切换。"
            )
        case .light:
            AppLocalization.text(
                "appearance.description_light",
                defaultValue: "始终使用明亮页面与深色文字。"
            )
        case .dark:
            AppLocalization.text(
                "appearance.description_dark",
                defaultValue: "始终使用深色页面与浅色文字。"
            )
        }
    }
}

@MainActor
private func settingsSectionHeader(_ title: String) -> some View {
    Text(title)
        .font(ZhixingTypography.rowTitle)
        .zhixingForeground(.heading)
}
