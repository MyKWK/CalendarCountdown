import Foundation

/// Limits and retirement flags for the main-window glass overlay.
///
/// User-facing glass is retired: behind-window blending punched the desktop
/// wallpaper through the sidebar and lists. Clamp helpers stay so a future
/// opaque-safe implementation can reuse them without re-enabling punch-through.
public enum WindowGlassAppearance: Sendable {
    public static let enabledDefaultsKey = "appearance.windowGlassEnabled"
    public static let transparencyDefaultsKey = "appearance.windowGlassTransparency"

    /// When false, settings and window chrome must not activate glass.
    public static let userFacingEnabled = false

    /// Fully solid fill; the glass blur is covered.
    public static let minimumTransparency: Double = 0
    /// Remaining window fill at the most transparent setting.
    public static let minimumFillOpacity: Double = 0.10
    /// Hard cap so the window never goes fully transparent.
    public static let maximumTransparency: Double = 1 - minimumFillOpacity
    public static let defaultTransparency: Double = 0.40

    public static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultTransparency }
        return min(max(value, minimumTransparency), maximumTransparency)
    }

    /// Opaque fill drawn over the glass. Inverse of transparency, never below
    /// `minimumFillOpacity`.
    public static func fillOpacity(transparency: Double) -> Double {
        max(1 - clamped(transparency), minimumFillOpacity)
    }

    public static func percent(_ transparency: Double) -> Int {
        Int((clamped(transparency) * 100).rounded())
    }

    /// Writes `false` for existing and missing enabled flags so an upgrade
    /// cannot keep punch-through glass from a previous default.
    public static func retireUserFacingPreference(in defaults: UserDefaults) {
        defaults.set(false, forKey: enabledDefaultsKey)
    }

    public static func isUserFacingGlassActive(
        enabledFlag: Bool,
        reduceTransparency: Bool
    ) -> Bool {
        userFacingEnabled && enabledFlag && !reduceTransparency
    }
}
