import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol SingleInstanceLocking: AnyObject {
    func inspect() -> SingleInstanceClaim?
    func tryAcquire(_ claim: SingleInstanceClaim) -> SingleInstanceLockResult
    func release(pid: Int32)
}

public enum ProcessLiveness: Sendable {
    public static func isRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    public static func executablePath(of pid: Int32) -> String? {
        #if os(macOS)
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }

    /// A lock holder is live only when the PID exists and still points at this product.
    public static func isLiveHolder(_ claim: SingleInstanceClaim) -> Bool {
        guard isRunning(claim.pid) else { return false }
        if claim.pid == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        guard let runningPath = executablePath(of: claim.pid), !runningPath.isEmpty else {
            return true
        }
        if !claim.executablePath.isEmpty {
            let claimed = AppInstanceIdentity.standardizedPath(claim.executablePath)
            let running = AppInstanceIdentity.standardizedPath(runningPath)
            if claimed == running {
                return true
            }
            return AppInstanceIdentity.isProductMainExecutable(path: running)
                && AppInstanceIdentity.isProductMainExecutable(path: claimed)
        }
        return AppInstanceIdentity.isProductMainExecutable(path: runningPath)
    }
}

/// Cross-process lock under Application Support/CalendarCountdown/Runtime.
/// That folder is independent of the .app location (official vs DerivedData)
/// and is not the countdown SQLite / selections store.
public final class FileSingleInstanceLock: SingleInstanceLocking, @unchecked Sendable {
    public let fileURL: URL
    private let mutexURL: URL
    private let fileManager: FileManager
    private let stateLock = NSLock()
    private var fd: Int32 = -1
    private var heldPID: Int32?

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.mutexURL = fileURL.appendingPathExtension("mutex")
        self.fileManager = fileManager
    }

    public static func productLock(fileManager: FileManager = .default) throws -> FileSingleInstanceLock {
        let root = try SharedContainer.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("Runtime", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return FileSingleInstanceLock(
            fileURL: root.appendingPathComponent("single-instance.lock"),
            fileManager: fileManager
        )
    }

    public func inspect() -> SingleInstanceClaim? {
        readClaim()
    }

    public func tryAcquire(_ claim: SingleInstanceClaim) -> SingleInstanceLockResult {
        stateLock.lock()
        defer { stateLock.unlock() }
        if heldPID == claim.pid, fd >= 0 {
            return .acquired
        }
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return withCoordinationLock {
            for _ in 0..<4 {
                if let existing = readClaim(), ProcessLiveness.isLiveHolder(existing) {
                    return .heldByExisting(existing)
                }
                if let existing = readClaim(), !ProcessLiveness.isLiveHolder(existing) {
                    _ = try? fileManager.removeItem(at: fileURL)
                }
                let created = open(
                    fileURL.path,
                    O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC,
                    0o644
                )
                if created >= 0 {
                    if flock(created, LOCK_EX | LOCK_NB) != 0 {
                        close(created)
                        _ = try? fileManager.removeItem(at: fileURL)
                        continue
                    }
                    guard writeClaim(claim, to: created) else {
                        flock(created, LOCK_UN)
                        close(created)
                        _ = try? fileManager.removeItem(at: fileURL)
                        continue
                    }
                    fd = created
                    heldPID = claim.pid
                    return .acquired
                }
                if errno == EEXIST, let existing = readClaim(), ProcessLiveness.isLiveHolder(existing) {
                    return .heldByExisting(existing)
                }
            }
            if let existing = readClaim() {
                return .heldByExisting(existing)
            }
            return .heldByExisting(claim)
        }
    }

    public func release(pid: Int32) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard heldPID == pid else { return }
        if fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
        heldPID = nil
        _ = try? fileManager.removeItem(at: fileURL)
    }

    deinit {
        if let pid = heldPID {
            release(pid: pid)
        }
    }

    private func withCoordinationLock<T>(_ body: () -> T) -> T {
        let mutex = open(mutexURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        if mutex >= 0 {
            _ = flock(mutex, LOCK_EX)
        }
        defer {
            if mutex >= 0 {
                flock(mutex, LOCK_UN)
                close(mutex)
            }
        }
        return body()
    }

    private func readClaim() -> SingleInstanceClaim? {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(SingleInstanceClaim.self, from: data)
    }

    private func writeClaim(_ claim: SingleInstanceClaim, to fd: Int32) -> Bool {
        guard let data = try? JSONEncoder().encode(claim) else { return false }
        ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        let written: Int = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return -1 }
            return write(fd, base, buffer.count)
        }
        guard written == data.count else { return false }
        fsync(fd)
        return true
    }
}

public enum SingleInstanceAcquisition: Equatable, Sendable {
    case becomeHolder
    case yieldToExisting(SingleInstanceClaim)
}

public enum SingleInstanceGate: Sendable {
    public static func resolve(
        current: AppInstanceSnapshot,
        lockResult: SingleInstanceLockResult,
        installDir: String = "/Applications"
    ) -> SingleInstanceAcquisition {
        switch lockResult {
        case .acquired:
            return .becomeHolder
        case let .heldByExisting(existing):
            let currentOfficial = AppInstanceIdentity.isOfficialInstall(
                bundlePath: current.bundlePath,
                installDir: installDir
            )
            let holderOfficial = AppInstanceIdentity.isOfficialInstall(
                bundlePath: existing.bundlePath,
                installDir: installDir
            )
            if currentOfficial && !holderOfficial {
                return .becomeHolder
            }
            return .yieldToExisting(existing)
        }
    }
}

extension MemorySingleInstanceLock: SingleInstanceLocking {}
