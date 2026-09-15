import CoreGraphics
import Foundation

/// Shared spacing, radius, and motion tokens for the 1.0.11 visual system.
///
/// Keep numeric values here so pages do not invent parallel 5 / 10 / 18 pt scales.
public enum ZhixingMetrics: Sendable {
    public static let space4: CGFloat = 4
    public static let space8: CGFloat = 8
    public static let space12: CGFloat = 12
    public static let space16: CGFloat = 16
    public static let space20: CGFloat = 20
    public static let space24: CGFloat = 24
    public static let space32: CGFloat = 32

    public static let pageInset: CGFloat = 24
    public static let sidebarMinWidth: CGFloat = 220
    public static let sidebarIdealWidth: CGFloat = 236
    public static let sidebarMaxWidth: CGFloat = 248

    public static let cornerSmall: CGFloat = 8
    public static let cornerSheet: CGFloat = 12
    public static let cornerContainer: CGFloat = 16

    public static let identityMarkWidth: CGFloat = 3.5
    public static let completionRingSize: CGFloat = 21
    public static let glassStrokeWidth: CGFloat = 0.75
    public static let accentFillMaxOpacity: Double = 0.12

    public static let motionFast: Double = 0.16
    public static let motionStandard: Double = 0.20
    public static let motionSlow: Double = 0.24
}

/// Surface roles layered over the window-level blurred backdrop.
public enum ZhixingSurfaceRole: String, CaseIterable, Equatable, Sendable {
    case canvas
    case sidebar
    case grouped
    case elevated
    case row
    case sheet
}

/// Washes drawn over window frost. Broad areas stay milky and quiet while rows
/// are almost clear until hover, matching Codex's low-chrome hierarchy.
public enum ZhixingSurfaceFill: Sendable {
    public static let minimumReadable: Double = 0.04

    public static let canvasLight: Double = 0.46
    public static let canvasDark: Double = 0.50
    public static let sidebarLight: Double = 0.28
    public static let sidebarDark: Double = 0.34
    public static let groupedLight: Double = 0.10
    public static let groupedDark: Double = 0.16
    public static let elevatedLight: Double = 0.38
    public static let elevatedDark: Double = 0.42
    public static let rowLight: Double = 0.04
    public static let rowDark: Double = 0.06
    public static let rowHoverLight: Double = 0.15
    public static let rowHoverDark: Double = 0.16
    public static let sheetLight: Double = 0.78
    public static let sheetDark: Double = 0.74
    public static let identityWashLight: Double = 0.045
    public static let identityWashDark: Double = 0.06

    public static func opacity(
        for role: ZhixingSurfaceRole,
        isDark: Bool,
        hovering: Bool = false,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        overallTransparency: Double = WindowGlassAppearance.defaultTransparency
    ) -> Double {
        if reduceTransparency || increaseContrast { return 1 }
        return scaled(
            max(baseOpacity(for: role, isDark: isDark, hovering: hovering), minimumReadable),
            overallTransparency: overallTransparency
        )
    }

    /// Scales a default-recipe fill so overall transparency 0 is solid and the
    /// default slider position keeps the authored sidebar-vs-canvas gap.
    public static func scaled(
        _ base: Double,
        overallTransparency: Double
    ) -> Double {
        let transparency = WindowGlassAppearance.clamped(overallTransparency)
        if transparency <= WindowGlassAppearance.minimumTransparency { return 1 }
        let defaultTransparency = WindowGlassAppearance.defaultTransparency
        guard defaultTransparency > 0 else { return 1 }
        if transparency <= defaultTransparency {
            let openness = max(0, min(1, 1 - base))
            return min(1, max(1 - openness * (transparency / defaultTransparency), minimumReadable))
        }

        let extraRange = max(WindowGlassAppearance.maximumTransparency - defaultTransparency, 0.000_1)
        let extraProgress = min(1, (transparency - defaultTransparency) / extraRange)
        let fill = base * (1 - 0.65 * extraProgress)
        return min(1, max(fill, minimumReadable))
    }

    public static func usesMaterial(
        for role: ZhixingSurfaceRole,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        overallTransparency: Double = WindowGlassAppearance.defaultTransparency
    ) -> Bool {
        if reduceTransparency || increaseContrast { return false }
        if WindowGlassAppearance.clamped(overallTransparency) <= WindowGlassAppearance.minimumTransparency {
            return false
        }
        switch role {
        case .canvas, .grouped, .row, .sheet:
            return false
        case .sidebar, .elevated:
            return true
        }
    }

    private static func baseOpacity(
        for role: ZhixingSurfaceRole,
        isDark: Bool,
        hovering: Bool
    ) -> Double {
        switch role {
        case .canvas:
            isDark ? canvasDark : canvasLight
        case .sidebar:
            isDark ? sidebarDark : sidebarLight
        case .grouped:
            isDark ? groupedDark : groupedLight
        case .elevated:
            isDark ? elevatedDark : elevatedLight
        case .row:
            if hovering {
                isDark ? rowHoverDark : rowHoverLight
            } else {
                isDark ? rowDark : rowLight
            }
        case .sheet:
            isDark ? sheetDark : sheetLight
        }
    }
}

/// Compact iCloud capsule states shown in the toolbar. This is presentation only.
public enum CloudSyncPresentation: String, Equatable, Sendable {
    case localOnly
    case enabled
    case syncing
    case synced
    case failed

    public var title: String {
        switch self {
        case .localOnly:
            AppLocalization.text("sync.state.local", defaultValue: "仅本机")
        case .enabled:
            AppLocalization.text("sync.state.enabled", defaultValue: "已开启")
        case .syncing:
            AppLocalization.text("sync.state.syncing", defaultValue: "同步中")
        case .synced:
            AppLocalization.text("sync.state.synced", defaultValue: "已同步")
        case .failed:
            AppLocalization.text("sync.state.failed", defaultValue: "失败")
        }
    }

    public var accessibilityValue: String {
        switch self {
        case .enabled:
            AppLocalization.text(
                "sync.state.enabled_pending",
                defaultValue: "已开启，待首次同步"
            )
        default:
            title
        }
    }

    public var systemImage: String {
        switch self {
        case .localOnly: "icloud"
        case .enabled: "icloud"
        case .syncing: "icloud"
        case .synced: "icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        }
    }

    public static func resolve(
        mode: CloudSyncMode,
        isSyncing: Bool,
        hasError: Bool,
        status: CloudSyncStatus?
    ) -> CloudSyncPresentation {
        guard mode == .iCloud else { return .localOnly }
        if hasError { return .failed }
        if isSyncing { return .syncing }
        if let status {
            switch status.account {
            case .noAccount, .restricted, .signedOut, .temporarilyUnavailable:
                return .failed
            case .unknown, .available, .couldNotDetermine, .switched:
                break
            }
            if status.lastFetchAt != nil || status.lastSendAt != nil {
                return .synced
            }
        }
        return .enabled
    }
}

public struct CompletedTrailAppearance: Equatable, Sendable {
    public var opacity: Double
    public var saturation: Double
    public var veil: Double

    public init(opacity: Double, saturation: Double, veil: Double) {
        self.opacity = opacity
        self.saturation = saturation
        self.veil = veil
    }
}

/// Viewport-aware fade for completed tasks. Resting depth fades the trail;
/// scrolling a card into the reading band restores contrast.
public enum CompletedTrailPresentation: Sendable {
    public static let readableOpacity: Double = 0.96
    public static let restingFloor: Double = 0.08
    public static let highContrastFloor: Double = 0.50

    public static func partition<T>(_ items: [T], isCompleted: (T) -> Bool) -> (open: [T], completed: [T]) {
        (items.filter { !isCompleted($0) }, items.filter(isCompleted))
    }

    public static func readingFocus(normalizedY: Double) -> Double {
        let innerStart = 0.14
        let innerEnd = 0.48
        let outerStart = -0.02
        let outerEnd = 0.72
        if normalizedY >= innerStart && normalizedY <= innerEnd { return 1 }
        if normalizedY < innerStart {
            return clamped((normalizedY - outerStart) / (innerStart - outerStart))
        }
        return clamped((outerEnd - normalizedY) / (outerEnd - innerEnd))
    }

    public static func resting(index: Int, highContrast: Bool) -> CompletedTrailAppearance {
        let depth = Double(max(index, 0))
        let floor = highContrast ? highContrastFloor : restingFloor
        let opacity = max(floor, 0.80 * pow(0.60, depth))
        let saturation = max(highContrast ? 0.72 : 0.14, pow(0.58, depth))
        let veil = highContrast
            ? min(0.16, 0.04 * depth)
            : min(0.58, 0.08 + 0.11 * depth)
        return CompletedTrailAppearance(opacity: opacity, saturation: saturation, veil: veil)
    }

    public static func resolve(
        index: Int,
        normalizedY: Double?,
        isHighlighted: Bool,
        highContrast: Bool
    ) -> CompletedTrailAppearance {
        let restingAppearance = resting(index: index, highContrast: highContrast)
        let readable = CompletedTrailAppearance(
            opacity: highContrast ? 1 : readableOpacity,
            saturation: 1,
            veil: 0
        )
        let focus: Double
        if isHighlighted {
            focus = 1
        } else if let normalizedY {
            focus = readingFocus(normalizedY: normalizedY)
        } else {
            focus = 0
        }
        return mix(restingAppearance, readable, t: focus)
    }

    private static func mix(
        _ from: CompletedTrailAppearance,
        _ to: CompletedTrailAppearance,
        t: Double
    ) -> CompletedTrailAppearance {
        let amount = clamped(t)
        return CompletedTrailAppearance(
            opacity: from.opacity + (to.opacity - from.opacity) * amount,
            saturation: from.saturation + (to.saturation - from.saturation) * amount,
            veil: from.veil + (to.veil - from.veil) * amount
        )
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public enum ZhixingIdentity {
    /// Stable visual identity for records that have no stored color.
    public static func color(for id: UUID) -> MissionColor {
        let bytes = id.uuid
        let sum = Int(bytes.0) &+ Int(bytes.1) &+ Int(bytes.2) &+ Int(bytes.3)
            &+ Int(bytes.4) &+ Int(bytes.5) &+ Int(bytes.6) &+ Int(bytes.7)
            &+ Int(bytes.8) &+ Int(bytes.9) &+ Int(bytes.10) &+ Int(bytes.11)
            &+ Int(bytes.12) &+ Int(bytes.13) &+ Int(bytes.14) &+ Int(bytes.15)
        let index = abs(sum) % MissionColor.allCases.count
        return MissionColor.allCases[index]
    }
}
