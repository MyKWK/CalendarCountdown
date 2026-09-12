import Foundation

/// Stable, cross-platform identity colors for missions.
///
/// The stored value is a semantic identifier instead of a display RGB value.
/// Apple clients render it with adaptive system colors; other clients can map
/// the same identifiers to platform-appropriate light and dark variants.
public enum MissionColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case brown

    public static let defaultValue: MissionColor = .blue

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blue:
            AppLocalization.text("mission.color.blue", defaultValue: "天空蓝")
        case .indigo:
            AppLocalization.text("mission.color.indigo", defaultValue: "靛蓝")
        case .purple:
            AppLocalization.text("mission.color.purple", defaultValue: "紫罗兰")
        case .pink:
            AppLocalization.text("mission.color.pink", defaultValue: "粉红")
        case .red:
            AppLocalization.text("mission.color.red", defaultValue: "珊瑚红")
        case .orange:
            AppLocalization.text("mission.color.orange", defaultValue: "日落橙")
        case .yellow:
            AppLocalization.text("mission.color.yellow", defaultValue: "琥珀黄")
        case .green:
            AppLocalization.text("mission.color.green", defaultValue: "草木绿")
        case .mint:
            AppLocalization.text("mission.color.mint", defaultValue: "薄荷")
        case .teal:
            AppLocalization.text("mission.color.teal", defaultValue: "青绿")
        case .cyan:
            AppLocalization.text("mission.color.cyan", defaultValue: "冰青")
        case .brown:
            AppLocalization.text("mission.color.brown", defaultValue: "沙棕")
        }
    }

    /// Resolves both current semantic identifiers and legacy hex colors.
    /// Unknown legacy colors are mapped to the visually nearest palette color.
    public static func resolve(_ storedValue: String) -> MissionColor {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = MissionColor(rawValue: trimmed.lowercased()) {
            return exact
        }
        let legacyHex = trimmed.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        if legacyHex == "5B8DEF" { return .blue }
        guard let rgb = RGB(hex: trimmed) else { return defaultValue }
        return allCases.min { lhs, rhs in
            lhs.referenceRGB.distanceSquared(to: rgb) < rhs.referenceRGB.distanceSquared(to: rgb)
        } ?? defaultValue
    }

    public static func canonicalStorageValue(_ storedValue: String) -> String {
        resolve(storedValue).rawValue
    }

    /// Reference values are used only to migrate old arbitrary hex values.
    /// Rendering uses adaptive system colors and does not hard-code these RGBs.
    private var referenceRGB: RGB {
        switch self {
        case .blue: RGB(red: 0, green: 122, blue: 255)
        case .indigo: RGB(red: 88, green: 86, blue: 214)
        case .purple: RGB(red: 175, green: 82, blue: 222)
        case .pink: RGB(red: 255, green: 45, blue: 85)
        case .red: RGB(red: 255, green: 56, blue: 60)
        case .orange: RGB(red: 255, green: 141, blue: 40)
        case .yellow: RGB(red: 255, green: 204, blue: 0)
        case .green: RGB(red: 52, green: 199, blue: 89)
        case .mint: RGB(red: 0, green: 200, blue: 179)
        case .teal: RGB(red: 0, green: 199, blue: 190)
        case .cyan: RGB(red: 85, green: 190, blue: 240)
        case .brown: RGB(red: 162, green: 132, blue: 94)
        }
    }
}

private struct RGB: Sendable {
    let red: Int
    let green: Int
    let blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        red = Int((value >> 16) & 0xFF)
        green = Int((value >> 8) & 0xFF)
        blue = Int(value & 0xFF)
    }

    func distanceSquared(to other: RGB) -> Int {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        return redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta
    }
}
