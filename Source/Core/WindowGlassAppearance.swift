import Foundation

/// Codex-style window frost strength.
///
/// The appearance slider stores a single overall transparency. Surface fills
/// scale from that value while keeping the cool sidebar clearer than the canvas.
/// The window remains blurred and tinted at every supported value; it never
/// becomes a raw transparent sheet.
public enum WindowGlassAppearance: Sendable {
    public static let enabledDefaultsKey = "appearance.windowGlassEnabled"
    public static let transparencyDefaultsKey = "appearance.windowGlassTransparency"
    public static let blurStrengthDefaultsKey = "appearance.windowGlassBlurStrength"
    public static let codexGlassMigrationDefaultsKey = "appearance.codexGlass.v1"

    public static let userFacingEnabled = true

    /// Fully solid fill; the glass blur is covered.
    public static let minimumTransparency: Double = 0
    /// Remaining window fill at the most transparent setting.
    public static let minimumFillOpacity: Double = 0.24
    /// Hard cap so the window never goes fully transparent.
    public static let maximumTransparency: Double = 1 - minimumFillOpacity
    public static let defaultTransparency: Double = 0.42

    /// The blur recipe is deliberately independent from transparency: a user
    /// can keep a clear window fill while choosing how much desktop detail is
    /// softened behind it.
    public enum BlurStrength: String, CaseIterable, Identifiable, Sendable {
        case subtle
        case standard
        case strong

        public var id: String { rawValue }

        /// Radius, in points, of the additional backdrop softening pass.
        /// Keep these deliberately far apart so the setting is visually
        /// meaningful rather than a barely perceptible material variation.
        public var backdropBlurRadius: Double {
            switch self {
            case .subtle: 4
            case .standard: 14
            case .strong: 30
            }
        }
    }

    public static let defaultBlurStrength: BlurStrength = .standard

    public static func blurStrength(for rawValue: String?) -> BlurStrength {
        guard let rawValue else { return defaultBlurStrength }
        return BlurStrength(rawValue: rawValue) ?? defaultBlurStrength
    }

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

    /// Previous releases forcibly stored `false`; migrate that retired value
    /// once so the new Codex-style appearance is visible after upgrading.
    public static func activateCodexGlassPreference(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: codexGlassMigrationDefaultsKey) else { return }
        defaults.set(true, forKey: enabledDefaultsKey)
        defaults.set(true, forKey: codexGlassMigrationDefaultsKey)
    }

    public static func isUserFacingGlassActive(
        enabledFlag: Bool,
        reduceTransparency: Bool
    ) -> Bool {
        userFacingEnabled && enabledFlag && !reduceTransparency
    }
}
