#if os(macOS)
import AppKit
import CalendarCountdownCore

enum MacAppInstanceProbe {
    static func current(
        pid: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundle: Bundle = .main
    ) -> AppInstanceSnapshot {
        AppInstanceSnapshot(
            pid: pid,
            bundleIdentifier: bundle.bundleIdentifier,
            executablePath: bundle.executableURL?.path,
            bundlePath: bundle.bundlePath
        )
    }

    static func peers(excludingPID pid: Int32) -> [AppInstanceSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != pid else { return nil }
            guard AppInstanceIdentity.recognizes(bundleID: app.bundleIdentifier) else { return nil }
            return AppInstanceSnapshot(
                pid: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                executablePath: app.executableURL?.path,
                bundlePath: app.bundleURL?.path
            )
        }
    }

    static func activate(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        _ = app.activate()
    }

    static func requestOthersToYield() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(AppInstanceIdentity.yieldNotificationName),
            object: ProductConstants.appBundleIdentifier,
            userInfo: [
                "holderPID": String(ProcessInfo.processInfo.processIdentifier),
                "bundlePath": Bundle.main.bundlePath
            ],
            deliverImmediately: true
        )
    }
}
#endif
