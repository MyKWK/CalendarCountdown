import Foundation

/// Shared lookup used by the app, menu-bar popover, and widget.
///
/// The default values keep the command-line tool and tests readable even when
/// they run without an application resource bundle.
public enum AppLocalization {
    public static func text(_ key: String, defaultValue: String) -> String {
        Bundle.main.localizedString(
            forKey: key,
            value: defaultValue,
            table: "Localizable"
        )
    }

    public static func format(
        _ key: String,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(key, defaultValue: defaultValue),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
