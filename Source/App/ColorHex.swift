import CalendarCountdownCore
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

    static func missionIdentity(_ storedValue: String) -> Color {
        MissionColor.resolve(storedValue).swiftUIColor
    }
}

extension MissionColor {
    var swiftUIColor: Color {
        #if os(macOS)
        let light = lightPalette
        let dark = darkPalette
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.nsColor
                : light.nsColor
        })
        #elseif os(iOS)
        let light = lightPalette
        let dark = darkPalette
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        })
        #else
        return lightPalette.color
        #endif
    }

    /// Low-saturation, darker mission colors keep identity useful without the
    /// bright candy-chip appearance of the platform system palette.
    private var lightPalette: MissionPaletteRGB {
        switch self {
        case .blue: MissionPaletteRGB(62, 88, 112)
        case .indigo: MissionPaletteRGB(72, 72, 108)
        case .purple: MissionPaletteRGB(91, 67, 101)
        case .pink: MissionPaletteRGB(105, 67, 83)
        case .red: MissionPaletteRGB(108, 67, 68)
        case .orange: MissionPaletteRGB(108, 78, 54)
        case .yellow: MissionPaletteRGB(99, 86, 50)
        case .green: MissionPaletteRGB(61, 91, 68)
        case .mint: MissionPaletteRGB(58, 92, 82)
        case .teal: MissionPaletteRGB(52, 88, 89)
        case .cyan: MissionPaletteRGB(54, 90, 104)
        case .brown: MissionPaletteRGB(89, 75, 65)
        }
    }

    /// Dark appearance raises luminance only enough to preserve contrast while
    /// retaining the same restrained, mineral palette.
    private var darkPalette: MissionPaletteRGB {
        switch self {
        case .blue: MissionPaletteRGB(105, 137, 163)
        case .indigo: MissionPaletteRGB(117, 118, 160)
        case .purple: MissionPaletteRGB(142, 113, 151)
        case .pink: MissionPaletteRGB(154, 110, 127)
        case .red: MissionPaletteRGB(160, 105, 106)
        case .orange: MissionPaletteRGB(158, 120, 84)
        case .yellow: MissionPaletteRGB(151, 132, 79)
        case .green: MissionPaletteRGB(99, 137, 106)
        case .mint: MissionPaletteRGB(94, 139, 125)
        case .teal: MissionPaletteRGB(88, 133, 134)
        case .cyan: MissionPaletteRGB(91, 137, 153)
        case .brown: MissionPaletteRGB(135, 116, 102)
        }
    }

    #if os(macOS)
    var nsColor: NSColor {
        lightPalette.nsColor
    }
    #endif
}

private struct MissionPaletteRGB {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    #if os(macOS)
    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
    #elseif os(iOS)
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
    #endif
}
