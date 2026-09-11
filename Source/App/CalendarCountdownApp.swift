import AppKit
import CalendarCountdownCalendar
import CalendarCountdownCore
import CalendarCountdownPersistence
import Combine
import EventKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let workspace: WorkspaceModel
    let appearanceSettings = AppAppearanceSettings()
    private var mainWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var featuredEventCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var midnightRefreshTimer: Timer?
    private var diagnosticMaintenanceTimer: Timer?
    private var calendarDayRefreshPolicy = CalendarDayRefreshPolicy()
    private var broker: AppBrokerServer?
    private var cloudEngine: CloudKitSyncEngine?
    private var profileSession: CloudProfileSession?
    private let projections = AppleProjectionRuntime()

    override init() {
        let workspaceModel = WorkspaceModel()
        workspace = workspaceModel
        model = AppModel(
            repository: EventKitRepository(
                countdownStore: workspaceModel.workspace?.countdown ?? JSONCountdownIntentStore()
            )
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLogger.shared.configure(component: "app")
        DiagnosticLogger.shared.log(
            .notice,
            category: .lifecycle,
            event: "app.launch.completed",
            metadata: ["version": ProductConstants.version]
        )
        installDiagnosticMaintenance()
        observeAppearance()
        installStatusItem()
        installAutomaticCalendarDayRefresh()
        startDomainRuntime()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticLogger.shared.log(.notice, category: .lifecycle, event: "app.terminate.started")
        midnightRefreshTimer?.invalidate()
        diagnosticMaintenanceTimer?.invalidate()
        broker?.stop()
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
                workspace: workspace,
                appearanceSettings: appearanceSettings
            ) { [weak self] in
                self?.showSettings()
            }
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = AppLocalization.text("app.name", defaultValue: "知行")
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

    func showSettings() {
        if settingsWindowController == nil {
            let hostingController = NSHostingController(
                rootView: AppSettingsView(settings: appearanceSettings)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = AppLocalization.text(
                "window.settings",
                defaultValue: "设置"
            )
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 720, height: 440))
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
                defaultValue: "知行"
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
                workspace: workspace,
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

    private func installDiagnosticMaintenance() {
        performDiagnosticMaintenance()
        let timer = Timer(
            timeInterval: 24 * 60 * 60,
            target: self,
            selector: #selector(runDiagnosticMaintenance(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 15 * 60
        RunLoop.main.add(timer, forMode: .common)
        diagnosticMaintenanceTimer = timer
    }

    @objc private func runDiagnosticMaintenance(_ sender: Timer) {
        performDiagnosticMaintenance()
    }

    private func performDiagnosticMaintenance() {
        do {
            let removed = try DiagnosticLogger.shared.cleanup()
            DiagnosticLogger.shared.log(
                .info,
                category: .maintenance,
                event: "logs.cleanup.completed",
                metadata: [
                    "removed_files": String(removed),
                    "retention_days": String(ProductConstants.diagnosticLogRetentionDays)
                ]
            )
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .maintenance,
                event: "logs.cleanup.failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
        }
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

    // NSCalendarDayChanged can be posted from a background queue.  Keep this
    // Objective-C selector nonisolated and explicitly return to MainActor
    // before accessing the app delegate's main-actor state.
    @objc nonisolated private func calendarDayMayHaveChanged(_ sender: Any) {
        Task { @MainActor [weak self] in
            self?.handleCalendarDayMayHaveChanged()
        }
    }

    private func handleCalendarDayMayHaveChanged() {
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
                defaultValue: "知行 · 尚无追踪事件"
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
            defaultValue: "知行，%@，%@",
            event.title,
            CountdownCalculator.label(until: event.eventDate)
        ))
    }

    private func startDomainRuntime() {
        guard let store = workspace.workspace else { return }
        do {
            DiagnosticLogger.shared.setLocalDeviceID(store.db.deviceID)
            let token = try BrokerTokenStore.loadOrCreate()
            let registry = try CloudProfileRegistry.shared()
            let session = CloudProfileSession(workspace: store, registry: registry)
            profileSession = session
            let server = AppBrokerServer(
                workspace: store,
                projections: projections,
                token: token,
                profileSession: session
            )
            try server.start()
            broker = server
            workspace.projectionRuntime = projections
            workspace.onEnableCloudKit = { [weak self] in
                self?.startCloudKitIfNeeded()
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(cloudDidApply(_:)),
                name: .calendarCountdownCloudDidApply,
                object: nil
            )
            if (try? store.cloud.mode()) == .iCloud {
                startCloudKitIfNeeded()
            }
            Task { await workspace.reconcileProjections() }
            DiagnosticLogger.shared.log(
                .notice,
                category: .lifecycle,
                event: "domain_runtime.started",
                metadata: [
                    "broker_listening": String(server.isListening),
                    "cloud_mode": (try? store.cloud.mode().rawValue) ?? "unknown"
                ]
            )
        } catch {
            DiagnosticLogger.shared.log(
                .fault,
                category: .lifecycle,
                event: "domain_runtime.start_failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            workspace.errorMessage = error.localizedDescription
        }
    }

    fileprivate func startCloudKitIfNeeded() {
        guard let store = workspace.workspace else { return }
        guard CloudKitSyncEngine.hasRequiredContainerEntitlement else {
            try? store.cloud.setMode(.localOnly)
            workspace.reload()
            workspace.statusMessage = nil
            workspace.errorMessage = "当前安装包没有 iCloud 容器权限，无法开启同步。你的本机数据没有变化；请使用带正式 iCloud 签名的安装包。"
            DiagnosticLogger.shared.log(
                .warning,
                category: .sync,
                event: "sync.disabled.missing_entitlement"
            )
            return
        }
        do {
            if cloudEngine == nil {
                guard let profileSession else {
                    throw DomainError(
                        code: .icloudUnavailable,
                        message: "开启 iCloud 同步前必须绑定当前 CloudProfileSession，不能绕过账号隔离。"
                    )
                }
                let engine = CloudKitEngineFactory.make(
                    workspace: store,
                    profileSession: profileSession
                )
                engine.onDidApplyChanges = { [weak self] in
                    Task { @MainActor in
                        self?.workspace.reload()
                        await self?.workspace.reconcileProjections()
                        await self?.model.refresh()
                    }
                }
                engine.onWorkspaceChanged = { [weak self] newWorkspace in
                    Task { @MainActor in
                        self?.workspace.replaceWorkspace(newWorkspace)
                        self?.broker?.replaceWorkspace(newWorkspace)
                    }
                }
                _ = try engine.start()
                broker?.attachCloudEngine(engine)
                cloudEngine = engine
            }
            Task {
                do {
                    _ = try await self.cloudEngine?.syncNow()
                } catch {
                    DiagnosticLogger.shared.log(
                        .error,
                        category: .sync,
                        event: "sync.background.failed",
                        metadata: DiagnosticLogger.errorMetadata(error)
                    )
                }
            }
        } catch {
            try? store.cloud.setMode(.localOnly)
            workspace.reload()
            workspace.statusMessage = nil
            DiagnosticLogger.shared.log(
                .error,
                category: .sync,
                event: "sync.enable.failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            workspace.errorMessage = error.localizedDescription
        }
    }

    @objc nonisolated private func cloudDidApply(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.workspace.reload()
            await self?.workspace.reconcileProjections()
            await self?.model.refresh()
        }
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
            AppSettingsView(settings: appDelegate.appearanceSettings)
        }
    }
}

private struct MainWindowRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var appearanceSettings: AppAppearanceSettings
    let openSettings: () -> Void

    var body: some View {
        RootView(
            model: model,
            workspace: workspace,
            openSettings: openSettings
        )
            .frame(minWidth: 880, minHeight: 580)
            .tint(appearanceSettings.accentColor)
            .preferredColorScheme(appearanceSettings.appearanceMode.colorScheme)
            .task {
                await model.bootstrap()
                workspace.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                Task { await model.refresh() }
                Task { await workspace.reconcileProjections() }
            }
    }
}
