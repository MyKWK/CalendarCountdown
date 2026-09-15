import Foundation

public enum ProductConstants {
    public static let version = "1.0.20"
    public static let appGroupIdentifier = "group.app.calendarcountdown.CalendarCountdown"
    public static let legacyAppGroupIdentifier = "group.com.hashxjhuang.CalendarCountdown"
    /// Historical macOS app IDs that still identify 知行 and must not bypass the single-instance guard.
    public static let legacyMacAppBundleIdentifiers: Set<String> = [
        "com.hashxjhuang.CalendarCountdown"
    ]
    public static let widgetBundleIdentifier = "app.calendarcountdown.CalendarCountdown.Widget"
    public static let widgetKind = "CalendarCountdownWidget"
    public static let taskWidgetKind = "CalendarCountdownTasksWidget"
    public static let missionWidgetKind = "CalendarCountdownMissionsWidget"
    public static let habitWidgetKind = "CalendarCountdownHabitsWidget"
    public static let appBundleIdentifier = "app.calendarcountdown.CalendarCountdown"
    public static let mobileAppBundleIdentifier = "app.calendarcountdown.CalendarCountdown.ios"
    public static let mobileWidgetBundleIdentifier = "app.calendarcountdown.CalendarCountdown.ios.Widget"
    public static let cloudKitContainerIdentifier = "iCloud.app.calendarcountdown.CalendarCountdown"
    public static let brokerLaunchTimeout: TimeInterval = 8
    public static let managedURLScheme = "calendarcountdown"
    public static let managedURLHost = "event"
    public static let defaultProjectionYears = 10
    public static let defaultFetchDays = 1_826
    public static let suggestedBirthdayCalendarTitle = "生日"
    public static let diagnosticLogRetentionDays = 30
}
