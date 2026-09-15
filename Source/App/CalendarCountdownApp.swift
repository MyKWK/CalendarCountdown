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
    let overviewSettings = StatusBarOverviewSettings()
    let shortcuts = AppShortcutCoordinator()
    let settingsNavigation = AppSettingsNavigation()
    private var mainWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusBarCoordinator: StatusBarCoordinator?
    private var appearanceCancellable: AnyCancellable?
    private var midnightRefreshTimer: Timer?
    private var diagnosticMaintenanceTimer: Timer?
    private var calendarDayRefreshPolicy = CalendarDayRefreshPolicy()
    private var broker: AppBrokerServer?
    private var cloudEngine: CloudKitSyncEngine?
    private var profileSession: CloudProfileSession?
    private let projections = AppleProjectionRuntime()
    private var instanceLock: FileSingleInstanceLock?

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

    func applicationWillFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("-ui-test-mission-editor") {
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-calcount-allow-duplicate-instance") {
            return
        }
        acquireSingleInstanceOrExit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLogger.shared.configure(component: "app")
        DiagnosticLogger.shared.log(
            .notice,
            category: .lifecycle,
            event: "app.launch.completed",
            metadata: ["version": ProductConstants.version]
        )
        if ProcessInfo.processInfo.arguments.contains("-ui-test-mission-editor") {
            showMissionEditorHarness(
                narrow: ProcessInfo.processInfo.arguments.contains("-ui-test-narrow")
            )
            return
        }
        installDiagnosticMaintenance()
        observeAppearance()
        installStatusBarOverview()
        installAutomaticCalendarDayRefresh()
        startDomainRuntime()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSingleInstanceYield(_:)),
            name: Notification.Name(AppInstanceIdentity.yieldNotificationName),
            object: ProductConstants.appBundleIdentifier
        )
        shortcuts.startGlobalWake { [weak self] in
            self?.showMainWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticLogger.shared.log(.notice, category: .lifecycle, event: "app.terminate.started")
        midnightRefreshTimer?.invalidate()
        diagnosticMaintenanceTimer?.invalidate()
        statusBarCoordinator?.stop()
        broker?.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        instanceLock?.release(pid: ProcessInfo.processInfo.processIdentifier)
    }

    private func acquireSingleInstanceOrExit() {
        let current = MacAppInstanceProbe.current()
        let claim = SingleInstanceClaim.from(current)
        let lock: FileSingleInstanceLock
        if let product = try? FileSingleInstanceLock.productLock() {
            lock = product
        } else {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CalendarCountdown/Runtime/single-instance.lock")
            lock = FileSingleInstanceLock(fileURL: url)
        }
        instanceLock = lock
        for _ in 0..<40 {
            let result = lock.tryAcquire(claim)
            switch SingleInstanceGate.resolve(current: current, lockResult: result) {
            case .becomeHolder:
                if case .acquired = result {
                    MacAppInstanceProbe.requestOthersToYield()
                    return
                }
                MacAppInstanceProbe.requestOthersToYield()
                Thread.sleep(forTimeInterval: 0.05)
            case let .yieldToExisting(existing):
                MacAppInstanceProbe.activate(pid: existing.pid)
                exit(0)
            }
        }
        if case let .heldByExisting(existing) = lock.tryAcquire(claim) {
            MacAppInstanceProbe.activate(pid: existing.pid)
        }
        exit(0)
    }

    @objc private func handleSingleInstanceYield(_ notification: Notification) {
        let holderPID = (notification.userInfo?["holderPID"] as? String).flatMap(Int32.init) ?? 0
        if ProcessInfo.processInfo.processIdentifier == holderPID {
            return
        }
        if AppInstanceIdentity.isOfficialInstall(bundlePath: Bundle.main.bundlePath) {
            return
        }
        DiagnosticLogger.shared.log(
            .notice,
            category: .lifecycle,
            event: "app.instance.yielded",
            metadata: [
                "pid": String(ProcessInfo.processInfo.processIdentifier),
                "executable": Bundle.main.executablePath ?? ""
            ]
        )
        instanceLock?.release(pid: ProcessInfo.processInfo.processIdentifier)
        statusBarCoordinator?.stop()
        NSApp.terminate(nil)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await model.recoverAuthorization() }
        workspace.reload()
        statusBarCoordinator?.refresh()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the status item and global wake shortcut available after the user
        // closes the main window. Choosing "Quit 知行" still terminates the app.
        false
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        if mainWindowController == nil {
            let rootView = MainWindowRootView(
                model: model,
                workspace: workspace,
                appearanceSettings: appearanceSettings,
                shortcuts: shortcuts
            ) { [weak self] section in
                self?.showSettings(section: section)
            }
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            let window = NSWindow(contentViewController: hostingController)
            window.title = AppLocalization.text("app.name", defaultValue: "知行")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 1_120, height: 740))
            window.minSize = NSSize(width: 880, height: 580)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            installSidebarToggleAccessory(on: window)
            window.center()
            window.isReleasedWhenClosed = false
            mainWindowController = NSWindowController(window: window)
        }

        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(section: AppSettingsSection = .appearance) {
        settingsNavigation.selection = section
        if settingsWindowController == nil {
            let hostingController = NSHostingController(
                rootView: AppSettingsView(
                    settings: appearanceSettings,
                    overview: overviewSettings,
                    shortcuts: shortcuts,
                    workspace: workspace,
                    navigation: settingsNavigation
                )
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = AppLocalization.text(
                "window.settings",
                defaultValue: "设置"
            )
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            installSidebarToggleAccessory(on: window)
            window.setContentSize(NSSize(width: 760, height: 640))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installSidebarToggleAccessory(on window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: {
            $0.view.identifier?.rawValue == SidebarToggleTitlebarAccessoryController.identifier.rawValue
        }) else { return }
        window.addTitlebarAccessoryViewController(SidebarToggleTitlebarAccessoryController())
    }

    private func installStatusBarOverview() {
        let coordinator = StatusBarCoordinator(
            overview: overviewSettings,
            model: model,
            workspace: workspace
        ) { [weak self] section in
            self?.shortcuts.request(.selectSection(section))
            self?.showMainWindow()
        }
        statusBarCoordinator = coordinator
        coordinator.start()
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
            self?.workspace.reload()
            self?.statusBarCoordinator?.refresh()
        }
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
            workspace.markCloudSyncFinished(
                error: "当前安装包没有 iCloud 容器权限，无法开启同步。你的本机数据没有变化；请使用带正式 iCloud 签名的安装包。"
            )
            workspace.statusMessage = nil
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
            workspace.isCloudSyncing = true
            Task {
                do {
                    _ = try await self.cloudEngine?.syncNow()
                    self.workspace.markCloudSyncFinished(error: nil)
                } catch {
                    DiagnosticLogger.shared.log(
                        .error,
                        category: .sync,
                        event: "sync.background.failed",
                        metadata: DiagnosticLogger.errorMetadata(error)
                    )
                    self.workspace.markCloudSyncFinished(error: error.localizedDescription)
                }
            }
        } catch {
            try? store.cloud.setMode(.localOnly)
            workspace.statusMessage = nil
            DiagnosticLogger.shared.log(
                .error,
                category: .sync,
                event: "sync.enable.failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            workspace.markCloudSyncFinished(error: error.localizedDescription)
        }
    }

    @objc nonisolated private func cloudDidApply(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.workspace.reload()
            await self?.workspace.reconcileProjections()
            await self?.model.refresh()
            self?.statusBarCoordinator?.refresh()
        }
    }

    private func showMissionEditorHarness(narrow: Bool) {
        NSApp.setActivationPolicy(.regular)
        let size = MissionEditorLayout.fittingSize(
            available: narrow
                ? CGSize(width: 700, height: 520)
                : NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        )
        let root = MissionEditorSheet { _ in }
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = AppLocalization.text("mission.create.title", defaultValue: "新建使命")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.minSize = NSSize(
            width: min(MissionEditorLayout.minWidth, size.width),
            height: min(MissionEditorLayout.minHeight, size.height)
        )
        window.center()
        window.isReleasedWhenClosed = false
        mainWindowController = NSWindowController(window: window)
        mainWindowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class SidebarToggleTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    static let identifier = NSUserInterfaceItemIdentifier("app.sidebar.toggle.titlebar")

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .left

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        container.identifier = Self.identifier

        let button = NSButton(
            image: NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "收起或展开侧边栏")!,
            target: self,
            action: #selector(toggleSidebar(_:))
        )
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "收起或展开侧边栏"
        button.identifier = NSUserInterfaceItemIdentifier("mac-sidebar-toggle")
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        view = container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleSidebar(_ sender: NSButton) {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: sender)
    }
}

@main
@MainActor
struct CalendarCountdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppSettingsView(
                settings: appDelegate.appearanceSettings,
                overview: appDelegate.overviewSettings,
                shortcuts: appDelegate.shortcuts,
                workspace: appDelegate.workspace,
                navigation: appDelegate.settingsNavigation
            )
        }
        .commands {
            ShortcutCommandMenu(shortcuts: appDelegate.shortcuts)
        }
    }
}

private struct MainWindowRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var appearanceSettings: AppAppearanceSettings
    @ObservedObject var shortcuts: AppShortcutCoordinator
    let openSettings: (AppSettingsSection) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var glassActive: Bool {
        WindowGlassAppearance.isUserFacingGlassActive(
            enabledFlag: appearanceSettings.windowGlassEnabled,
            reduceTransparency: reduceTransparency
        )
    }

    var body: some View {
        RootView(
            model: model,
            workspace: workspace,
            openSettings: openSettings,
            shortcuts: shortcuts
        )
            .frame(minWidth: 880, minHeight: 580)
            .tint(appearanceSettings.accentColor)
            .preferredColorScheme(appearanceSettings.appearanceMode.colorScheme)
            .appSurfaceTransparency(appearanceSettings.windowGlassTransparency)
            .appMainWindowGlass(
                enabled: glassActive,
                transparency: appearanceSettings.windowGlassTransparency,
                blurRadius: appearanceSettings.windowGlassBlurRadius
            )
            .environment(\.appWindowGlassActive, glassActive)
            .task {
                await model.bootstrap()
                workspace.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                Task {
                    await model.recoverAuthorization()
                    await workspace.reconcileProjections()
                }
            }
    }
}
