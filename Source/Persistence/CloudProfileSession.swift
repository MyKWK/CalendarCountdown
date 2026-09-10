#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import Foundation

public struct CloudProfile: Equatable, Sendable {
    public var mode: CloudSyncMode
    public var accountHash: String

    public init(mode: CloudSyncMode, accountHash: String) {
        self.mode = mode
        self.accountHash = accountHash
    }

    public static let localOnly = CloudProfile(mode: .localOnly, accountHash: "local")
}

public final class CloudProfileSession: @unchecked Sendable {
    public private(set) var profile: CloudProfile
    private let fileManager: FileManager

    public init(profile: CloudProfile = .localOnly, fileManager: FileManager = .default) {
        self.profile = profile
        self.fileManager = fileManager
    }

    public func databaseURL() throws -> URL {
        let root = try SharedContainer.rootURL(fileManager: fileManager)
        if profile.mode == .localOnly {
            return try SharedContainer.sqliteDatabaseURL(fileManager: fileManager)
        }
        let directory = root
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profile.accountHash, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("calendarcountdown-v2.sqlite")
    }

    public func switchProfile(_ profile: CloudProfile) {
        self.profile = profile
    }
}
