import AppKit
import Combine
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
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

enum AppThemePreset: String, CaseIterable, Identifiable {
    case aiBlue
    case indigo
    case purple
    case pink
    case orange
    case yellow
    case green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiBlue: "AI 蓝"
        case .indigo: "靛蓝"
        case .purple: "紫色"
        case .pink: "粉色"
        case .orange: "橙色"
        case .yellow: "黄色"
        case .green: "绿色"
        }
    }

    var color: Color {
        switch self {
        case .aiBlue: Color(nsColor: .systemBlue)
        case .indigo: Color(nsColor: .systemIndigo)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .green: Color(nsColor: .systemGreen)
        }
    }
}

@MainActor
final class AppAppearanceSettings: ObservableObject {
    static let customThemeID = "custom"

    private enum Keys {
        static let themeID = "appearance.themeID"
        static let customColorHex = "appearance.customColorHex"
        static let mode = "appearance.mode"
    }

    private let defaults: UserDefaults

    @Published var selectedThemeID: String {
        didSet { defaults.set(selectedThemeID, forKey: Keys.themeID) }
    }

    @Published var customColorHex: String {
        didSet { defaults.set(customColorHex, forKey: Keys.customColorHex) }
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.mode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedThemeID = defaults.string(forKey: Keys.themeID)
        if storedThemeID == Self.customThemeID
            || AppThemePreset(rawValue: storedThemeID ?? "") != nil {
            selectedThemeID = storedThemeID ?? AppThemePreset.aiBlue.rawValue
        } else {
            selectedThemeID = AppThemePreset.aiBlue.rawValue
        }

        customColorHex = defaults.string(forKey: Keys.customColorHex) ?? "#0A84FF"
        appearanceMode = AppAppearanceMode(
            rawValue: defaults.string(forKey: Keys.mode) ?? ""
        ) ?? .system
    }

    var accentColor: Color {
        if let preset = AppThemePreset(rawValue: selectedThemeID) {
            return preset.color
        }
        return Color(hex: customColorHex)
    }

    var customColor: Color { Color(hex: customColorHex) }

    func select(_ preset: AppThemePreset) {
        selectedThemeID = preset.rawValue
    }

    func useCustomColor() {
        selectedThemeID = Self.customThemeID
    }

    func updateCustomColor(_ color: Color) {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
        let red = Int((converted.redComponent * 255).rounded())
        let green = Int((converted.greenComponent * 255).rounded())
        let blue = Int((converted.blueComponent * 255).rounded())
        customColorHex = String(format: "#%02X%02X%02X", red, green, blue)
        selectedThemeID = Self.customThemeID
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppAppearanceSettings

    var body: some View {
        Form {
            Section("主题颜色") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("颜色用于选中状态、主要按钮和交互强调；内容分类仍沿用 Apple 日历自身的颜色。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 14) {
                        ForEach(AppThemePreset.allCases) { preset in
                            ThemeSwatch(
                                title: preset.title,
                                color: preset.color,
                                isSelected: settings.selectedThemeID == preset.rawValue
                            ) {
                                settings.select(preset)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        ColorPicker(
                            "自定义颜色",
                            selection: Binding(
                                get: { settings.customColor },
                                set: { settings.updateCustomColor($0) }
                            ),
                            supportsOpacity: false
                        )
                        Spacer()
                        Text(settings.customColorHex.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button("使用自定义颜色") {
                            settings.useCustomColor()
                        }
                        .disabled(settings.selectedThemeID == AppAppearanceSettings.customThemeID)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("页面外观") {
                Picker("页面外观", selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(appearanceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 610, height: 390)
        .tint(settings.accentColor)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private var appearanceDescription: String {
        switch settings.appearanceMode {
        case .system: "根据 macOS 当前的浅色或深色外观自动切换。"
        case .light: "始终使用明亮页面与深色文字。"
        case .dark: "始终使用深色页面与浅色文字。"
        }
    }
}

private struct ThemeSwatch: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 34, height: 34)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
                        .padding(-4)
                }

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("主题颜色：\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0x8E8E93
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
