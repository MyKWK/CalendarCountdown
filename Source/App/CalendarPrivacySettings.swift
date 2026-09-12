import CalendarCountdownCore
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Opens the system calendar-privacy pane when EventKit can no longer prompt.
public enum CalendarPrivacySettings {
    public static func open() {
        #if os(macOS)
        NSWorkspace.shared.open(CalendarAccessRecovery.macOSCalendarPrivacyURL)
        #else
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
