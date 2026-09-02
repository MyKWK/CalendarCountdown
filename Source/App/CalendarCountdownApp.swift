import AppKit
import CalendarCountdownCore
import Combine
import EventKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let appearanceSettings = AppAppearanceSettings()
    private var mainWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var featuredEventCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var midnightRefreshTimer: Timer?
    private var calendarDayRefreshPolicy = CalendarDayRefreshPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearance()
        installStatusItem()
        installAutomaticCalendarDayRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        midnightRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        if mainWindowController == nil {
            let rootView = MainWindowRootView(
                model: model,
                appearanceSettings: appearanceSettings
            ) { [weak self] in
                self?.showAppearanceSettings()
            }
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = AppLocalization.text("app.name", defaultValue: "日历倒数")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1_040, height: 700))
            window.minSize = NSSize(width: 880, height: 580)
            window.center()
            window.isReleasedWhenClosed = false
            mainWindowController = NSWindowController(window: window)
        }

        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAppearanceSettings() {
        if settingsWindowController == nil {
            let hostingController = NSHostingController(
                rootView: AppearanceSettingsView(settings: appearanceSettings)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = AppLocalization.text(
                "window.appearance_settings",
                defaultValue: "外观设置"
            )
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 610, height: 390))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "calendar.badge.clock",
            accessibilityDescription: AppLocalization.text(
                "app.name",
                defaultValue: "日历倒数"
            )
        )
        item.button?.imagePosition = .imageLeading
        item.button?.imageHugsTitle = true
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        item.button?.target = self
        item.button?.action = #selector(toggleStatusPopover(_:))

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                model: model,
                appearanceSettings: appearanceSettings
            ) { [weak self] in
                    self?.statusPopover?.performClose(nil)
                    self?.showMainWindow()
                }
        )

        statusItem = item
        statusPopover = popover
        featuredEventCancellable = model.$featuredEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                self?.updateStatusItem(for: event)
            }
    }

    private func observeAppearance() {
        NSApp.appearance = appearanceSettings.appearanceMode.appKitAppearance
        appearanceCancellable = appearanceSettings.$appearanceMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { mode in
                NSApp.appearance = mode.appKitAppearance
            }
    }

    private func installAutomaticCalendarDayRefresh() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(calendarDayMayHaveChanged(_:)),
            name: .NSCalendarDayChanged,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(calendarDayMayHaveChanged(_:)),
            name: .NSSystemClockDidChange,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(calendarDayMayHaveChanged(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(calendarDayMayHaveChanged(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(calendarDayMayHaveChanged(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        scheduleNextMidnightRefresh()
    }

    private func scheduleNextMidnightRefresh(now: Date = Date()) {
        midnightRefreshTimer?.invalidate()
        let timer = Timer(
            fireAt: DateSupport.nextMidnight(after: now),
            interval: 0,
            target: self,
            selector: #selector(calendarDayMayHaveChanged(_:)),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        midnightRefreshTimer = timer
    }

    @objc private func calendarDayMayHaveChanged(_ sender: Any) {
        scheduleNextMidnightRefresh()
        guard calendarDayRefreshPolicy.shouldRefresh() else { return }
        Task { [weak self] in
            await self?.model.refresh()
        }
    }

    private func updateStatusItem(for event: CountdownEvent?) {
        guard let button = statusItem?.button else { return }
        guard let event else {
            button.title = ""
            button.toolTip = AppLocalization.text(
                "status_item.no_events",
                defaultValue: "日历倒数 · 尚无追踪事件"
            )
            return
        }

        let days = CountdownCalculator.daysRemaining(until: event.eventDate)
        button.title = days == 0
            ? AppLocalization.text("countdown.today", defaultValue: "今天")
            : String(days)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        button.toolTip = AppLocalization.format(
            "status_item.event_tooltip",
            defaultValue: "%@ · %@ · %@",
            event.title,
            formatter.string(from: event.eventDate),
            CountdownCalculator.label(until: event.eventDate)
        )
        button.setAccessibilityLabel(AppLocalization.format(
            "status_item.accessibility_label",
            defaultValue: "日历倒数，%@，%@",
            event.title,
            CountdownCalculator.label(until: event.eventDate)
        ))
    }

    @objc private func toggleStatusPopover(_ sender: Any?) {
        guard let popover = statusPopover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@main
@MainActor
struct CalendarCountdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppearanceSettingsView(settings: appDelegate.appearanceSettings)
        }
    }
}

private struct MainWindowRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var appearanceSettings: AppAppearanceSettings
    let openAppearanceSettings: () -> Void

    var body: some View {
        MainView(
            model: model,
            openAppearanceSettings: openAppearanceSettings
        )
            .frame(minWidth: 880, minHeight: 580)
            .tint(appearanceSettings.accentColor)
            .preferredColorScheme(appearanceSettings.appearanceMode.colorScheme)
            .task { await model.bootstrap() }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                Task { await model.refresh() }
            }
    }
}
