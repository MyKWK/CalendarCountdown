#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import Foundation

/// Process-wide app services. A `CloudProfileSession` is required so CloudKit
/// never runs against an unscoped database path.
public struct AppBroker: Sendable {
    public let session: CloudProfileSession
    public let database: AppDatabase
    public let syncEngine: CloudKitSyncEngine

    public init(session: CloudProfileSession, fileManager: FileManager = .default) throws {
        self.session = session
        self.database = try AppDatabase.open(
            at: try session.databaseURL(),
            backupDirectory: try SharedContainer.sqliteBackupDirectoryURL(fileManager: fileManager),
            fileManager: fileManager
        )
        try CountdownStore(db: database).importLegacyJSONIfNeeded(fileManager: fileManager)
        self.syncEngine = CloudKitSyncEngine(database: database, session: session)
    }

    public static func openShared(
        session: CloudProfileSession,
        fileManager: FileManager = .default,
        allowTemporaryFallback: Bool = true
    ) throws -> AppBroker {
        do {
            return try AppBroker(session: session, fileManager: fileManager)
        } catch {
            guard allowTemporaryFallback else { throw error }
            return try AppBroker.temporary(session: session, fileManager: fileManager)
        }
    }

    public static func temporary(
        session: CloudProfileSession,
        fileManager: FileManager = .default
    ) throws -> AppBroker {
        let database = try AppDatabase.openTemporary(fileManager: fileManager)
        return AppBroker(session: session, database: database)
    }

    init(session: CloudProfileSession, database: AppDatabase) {
        self.session = session
        self.database = database
        self.syncEngine = CloudKitSyncEngine(database: database, session: session)
    }
}
