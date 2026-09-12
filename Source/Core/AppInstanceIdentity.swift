import Foundation

public struct AppInstanceSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var bundleIdentifier: String?
    public var executablePath: String?
    public var bundlePath: String?

    public init(
        pid: Int32,
        bundleIdentifier: String? = nil,
        executablePath: String? = nil,
        bundlePath: String? = nil
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.bundlePath = bundlePath
    }
}

public enum SingleInstanceDecision: Equatable, Sendable {
    case becomeHolder
    case yieldToExisting(pid: Int32)
}

public struct SingleInstanceClaim: Equatable, Codable, Sendable {
    public var pid: Int32
    public var executablePath: String
    public var bundleIdentifier: String
    public var bundlePath: String?

    public init(
        pid: Int32,
        executablePath: String,
        bundleIdentifier: String,
        bundlePath: String? = nil
    ) {
        self.pid = pid
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
    }

    public var snapshot: AppInstanceSnapshot {
        AppInstanceSnapshot(
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            bundlePath: bundlePath
        )
    }

    public static func from(_ snapshot: AppInstanceSnapshot) -> SingleInstanceClaim {
        SingleInstanceClaim(
            pid: snapshot.pid,
            executablePath: snapshot.executablePath ?? "",
            bundleIdentifier: snapshot.bundleIdentifier ?? "",
            bundlePath: snapshot.bundlePath
        )
    }
}

public enum SingleInstanceLockResult: Equatable, Sendable {
    case acquired
    case heldByExisting(SingleInstanceClaim)
}

/// Identity and path rules for the macOS 知行 app.
///
/// Official install is `/Applications/知行.app`. A DerivedData Release/Debug
/// product with the same bundle ID is still this product, but it is never the
/// canonical holder.
public enum AppInstanceIdentity: Sendable {
    public static let officialAppFileName = "知行.app"
    public static let productExecutableName = "CalendarCountdown"
    public static let yieldNotificationName = "app.calendarcountdown.CalendarCountdown.yieldInstance"

    public static var recognizedMacAppBundleIdentifiers: Set<String> {
        Set([ProductConstants.appBundleIdentifier])
            .union(ProductConstants.legacyMacAppBundleIdentifiers)
    }

    public static func recognizes(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return recognizedMacAppBundleIdentifiers.contains(bundleID)
    }

    /// Unknown bundle IDs are never managed, even if the executable name looks familiar.
    public static func shouldManageInstance(bundleID: String?, executablePath: String? = nil) -> Bool {
        recognizes(bundleID: bundleID)
    }

    public static func isOfficialInstall(
        bundlePath: String?,
        installDir: String = "/Applications"
    ) -> Bool {
        guard let bundlePath, !bundlePath.isEmpty else { return false }
        let app = standardizedPath(bundlePath)
        let official = standardizedPath((installDir as NSString).appendingPathComponent(officialAppFileName))
        return app == official || app.hasPrefix(official + "/")
    }

    public static func isDerivedDataProduct(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let value = path.replacingOccurrences(of: "\\", with: "/")
        return value.contains("/Library/Developer/Xcode/DerivedData/")
            && value.contains("/Build/Products/")
            && value.contains("/CalendarCountdown.app")
    }

    public static func isProductMainExecutable(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let value = path.replacingOccurrences(of: "\\", with: "/")
        return value.hasSuffix("/Contents/MacOS/\(productExecutableName)")
            && !value.contains(".appex/")
    }

    public static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

public enum SingleInstancePolicy: Sendable {
    public static func decide(
        current: AppInstanceSnapshot,
        others: [AppInstanceSnapshot],
        installDir: String = "/Applications"
    ) -> SingleInstanceDecision {
        let peers = others.filter { peer in
            peer.pid != current.pid
                && AppInstanceIdentity.shouldManageInstance(bundleID: peer.bundleIdentifier)
        }
        guard !peers.isEmpty else { return .becomeHolder }

        let currentIsOfficial = AppInstanceIdentity.isOfficialInstall(
            bundlePath: current.bundlePath,
            installDir: installDir
        )
        let officialPeers = peers.filter {
            AppInstanceIdentity.isOfficialInstall(bundlePath: $0.bundlePath, installDir: installDir)
        }

        if currentIsOfficial {
            if let otherOfficial = officialPeers.min(by: { $0.pid < $1.pid }),
               otherOfficial.pid < current.pid {
                return .yieldToExisting(pid: otherOfficial.pid)
            }
            return .becomeHolder
        }

        if let official = officialPeers.min(by: { $0.pid < $1.pid }) {
            return .yieldToExisting(pid: official.pid)
        }
        if let existing = peers.min(by: { $0.pid < $1.pid }) {
            return .yieldToExisting(pid: existing.pid)
        }
        return .becomeHolder
    }
}

public final class MemorySingleInstanceLock: @unchecked Sendable {
    private let lock = NSLock()
    private var claim: SingleInstanceClaim?

    public init() {}

    public func inspect() -> SingleInstanceClaim? {
        lock.lock()
        defer { lock.unlock() }
        return claim
    }

    public func tryAcquire(_ claim: SingleInstanceClaim) -> SingleInstanceLockResult {
        lock.lock()
        defer { lock.unlock() }
        if let existing = self.claim, existing.pid != claim.pid {
            return .heldByExisting(existing)
        }
        self.claim = claim
        return .acquired
    }

    public func release(pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        if claim?.pid == pid {
            claim = nil
        }
    }
}

public enum CountdownPresentationRecovery: Sendable {
    /// Keep the last tracked-events document when selections still exist but
    /// nothing rematched, so a truncated EventKit fetch cannot wipe user data.
    public static func shouldReplaceTrackedDocument(
        visibleEventCount: Int,
        selectionCount: Int
    ) -> Bool {
        visibleEventCount > 0 || selectionCount == 0
    }
}

public enum EventKitQueryWindow: Sendable {
    /// Splits a wide EventKit fetch into year-aligned slices so providers do
    /// not truncate a single multi-year predicate.
    public static func yearSlices(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [(start: Date, end: Date)] {
        guard start < end else { return [] }
        var slices: [(Date, Date)] = []
        var cursor = start
        var guardCounter = 0
        while cursor < end && guardCounter < 32 {
            guardCounter += 1
            let year = calendar.component(.year, from: cursor)
            guard let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
                break
            }
            let sliceEnd = min(yearEnd, end)
            if sliceEnd > cursor {
                slices.append((cursor, sliceEnd))
            }
            cursor = sliceEnd
        }
        return slices
    }
}
