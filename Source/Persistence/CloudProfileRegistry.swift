import CalendarCountdownCore
import Foundation
import GRDB

public struct CloudProfileCatalog: Equatable, Codable, Sendable {
    public var activeAccountHash: String?
    public var lockedAccountHashes: [String]

    public init(activeAccountHash: String? = nil, lockedAccountHashes: [String] = []) {
        self.activeAccountHash = activeAccountHash
        self.lockedAccountHashes = lockedAccountHashes
    }
}

public struct CloudProfileSwitch: Equatable, Sendable {
    public var previousAccountHash: String?
    public var activeAccountHash: String?
    public var databaseURL: URL
    public var lockedAccountHashes: [String]
    public var didChangeDatabase: Bool

    public init(
        previousAccountHash: String?,
        activeAccountHash: String?,
        databaseURL: URL,
        lockedAccountHashes: [String],
        didChangeDatabase: Bool
    ) {
        self.previousAccountHash = previousAccountHash
        self.activeAccountHash = activeAccountHash
        self.databaseURL = databaseURL
        self.lockedAccountHashes = lockedAccountHashes
        self.didChangeDatabase = didChangeDatabase
    }
}

public struct CloudProfileRegistry: @unchecked Sendable {
    public let rootURL: URL
    public let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public static func shared(fileManager: FileManager = .default) throws -> CloudProfileRegistry {
        CloudProfileRegistry(rootURL: try SharedContainer.rootURL(fileManager: fileManager), fileManager: fileManager)
    }

    public var catalogURL: URL {
        rootURL.appendingPathComponent("cloud-profile-catalog.json")
    }

    public var unsignedDatabaseURL: URL {
        rootURL.appendingPathComponent("calendarcountdown-v2.sqlite")
    }

    public var backupDirectoryURL: URL {
        rootURL.appendingPathComponent("Backups", isDirectory: true)
    }

    public func profileDatabaseURL(accountHash: String) -> URL {
        rootURL
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(accountHash, isDirectory: true)
            .appendingPathComponent("calendarcountdown-v2.sqlite")
    }

    public func loadCatalog() throws -> CloudProfileCatalog {
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            return CloudProfileCatalog()
        }
        let data = try Data(contentsOf: catalogURL)
        return try JSONCoding.decoder().decode(CloudProfileCatalog.self, from: data)
    }

    public func saveCatalog(_ catalog: CloudProfileCatalog) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder(pretty: true).encode(catalog)
        try data.write(to: catalogURL, options: .atomic)
    }

    public func activeDatabaseURL() throws -> URL {
        let catalog = try loadCatalog()
        if let hash = catalog.activeAccountHash, !hash.isEmpty {
            return profileDatabaseURL(accountHash: hash)
        }
        return unsignedDatabaseURL
    }

    public func isLocked(_ accountHash: String) throws -> Bool {
        try loadCatalog().lockedAccountHashes.contains(accountHash)
    }
}

public final class CloudProfileSession: @unchecked Sendable {
    public private(set) var workspace: Workspace
    public let registry: CloudProfileRegistry
    public var onWorkspaceChanged: (@Sendable (Workspace) -> Void)?

    public init(workspace: Workspace, registry: CloudProfileRegistry) {
        self.workspace = workspace
        self.registry = registry
    }

    public var activeAccountHash: String? {
        (try? registry.loadCatalog())?.activeAccountHash
    }

    @discardableResult
    public func activateAccount(hash: String) throws -> CloudProfileSwitch {
        let normalized = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw DomainError.validation("CloudKit 账号 hash 不能为空。")
        }
        var catalog = try registry.loadCatalog()
        let previous = catalog.activeAccountHash
        let destination = registry.profileDatabaseURL(accountHash: normalized)
        let currentURL = URL(fileURLWithPath: workspace.db.path)
        if previous == normalized, currentURL.standardizedFileURL.path == destination.standardizedFileURL.path {
            return CloudProfileSwitch(
                previousAccountHash: previous,
                activeAccountHash: normalized,
                databaseURL: destination,
                lockedAccountHashes: catalog.lockedAccountHashes,
                didChangeDatabase: false
            )
        }

        if let previous, previous != normalized, !catalog.lockedAccountHashes.contains(previous) {
            catalog.lockedAccountHashes.append(previous)
        }

        let destinationExists = registry.fileManager.fileExists(atPath: destination.path)
        let opened: AppDatabase
        if destinationExists {
            try workspace.db.close()
            opened = try AppDatabase.open(
                at: destination,
                backupDirectory: registry.backupDirectoryURL,
                fileManager: registry.fileManager
            )
        } else if previous == nil {
            opened = try AppDatabase.open(
                at: destination,
                backupDirectory: registry.backupDirectoryURL,
                fileManager: registry.fileManager
            )
            try workspace.db.copyContents(to: opened)
            try workspace.db.close()
            try Self.removeDatabaseFiles(at: currentURL, fileManager: registry.fileManager)
        } else {
            try workspace.db.close()
            opened = try AppDatabase.open(
                at: destination,
                backupDirectory: registry.backupDirectoryURL,
                fileManager: registry.fileManager
            )
        }

        catalog.activeAccountHash = normalized
        catalog.lockedAccountHashes.removeAll { $0 == normalized }
        try registry.saveCatalog(catalog)
        workspace = Workspace(db: opened, countdown: workspace.countdown)
        onWorkspaceChanged?(workspace)
        return CloudProfileSwitch(
            previousAccountHash: previous,
            activeAccountHash: normalized,
            databaseURL: destination,
            lockedAccountHashes: catalog.lockedAccountHashes,
            didChangeDatabase: true
        )
    }

    @discardableResult
    public func lockCurrentAccount() throws -> CloudProfileSwitch {
        var catalog = try registry.loadCatalog()
        let previous = catalog.activeAccountHash
        if let previous, !catalog.lockedAccountHashes.contains(previous) {
            catalog.lockedAccountHashes.append(previous)
        }
        catalog.activeAccountHash = nil
        try registry.saveCatalog(catalog)
        try workspace.db.close()
        let unsigned = try AppDatabase.open(
            at: registry.unsignedDatabaseURL,
            backupDirectory: registry.backupDirectoryURL,
            fileManager: registry.fileManager
        )
        workspace = Workspace(db: unsigned, countdown: workspace.countdown)
        onWorkspaceChanged?(workspace)
        return CloudProfileSwitch(
            previousAccountHash: previous,
            activeAccountHash: nil,
            databaseURL: registry.unsignedDatabaseURL,
            lockedAccountHashes: catalog.lockedAccountHashes,
            didChangeDatabase: true
        )
    }

    private static func removeDatabaseFiles(at url: URL, fileManager: FileManager) throws {
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: file.path) {
                try fileManager.removeItem(at: file)
            }
        }
    }
}
