#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import CloudKit
import Foundation

public enum CloudKitSyncError: LocalizedError {
    case fetchFailed
    case accountUnavailable

    public var errorDescription: String? {
        switch self {
        case .fetchFailed:
            "从 iCloud 拉取变更失败，未更新 lastFetchAt。"
        case .accountUnavailable:
            "当前 iCloud 账户不可用，已保持本地 lastFetchAt 不变。"
        }
    }
}

/// CloudKit 同步引擎。必须持有 `CloudProfileSession`，禁止无账号隔离地直接构造。
public final class CloudKitSyncEngine: @unchecked Sendable {
    public let database: AppDatabase
    public let session: CloudProfileSession
    public let containerIdentifier: String

    /// Test seam: when set, `fetchChanges()` returns this value instead of talking to CloudKit.
    public var fetchChangesOverride: (() async -> CloudFetchOutcome)?

    public init(
        database: AppDatabase,
        session: CloudProfileSession,
        containerIdentifier: String = ProductConstants.cloudKitContainerIdentifier
    ) {
        self.database = database
        self.session = session
        self.containerIdentifier = containerIdentifier
    }

    public func syncNow() async throws {
        guard session.profile.mode != .localOnly else { return }
        let fetchOutcome = try await fetchChanges()
        try database.recordFetchOutcome(fetchOutcome)
        guard fetchOutcome != .failed else {
            throw CloudKitSyncError.fetchFailed
        }
        _ = try await sendOutbox()
    }

    public func fetchChanges() async throws -> CloudFetchOutcome {
        if let fetchChangesOverride {
            return await fetchChangesOverride()
        }
        if session.profile.mode == .localOnly {
            return .empty
        }
        do {
            let container = CKContainer(identifier: containerIdentifier)
            let status = try await container.accountStatus()
            guard status == .available else {
                return .failed
            }
            return .empty
        } catch {
            return .failed
        }
    }

    public func sendOutbox() async throws -> Int {
        let items = try CountdownStore(db: database).pendingOutbox()
        guard session.profile.mode != .localOnly else { return 0 }
        for item in items {
            _ = try CloudRecordCodec.fields(from: item)
        }
        return items.count
    }
}

enum CloudRecordCodec {
    static func fields(from item: CloudOutboxItem) throws -> [String: String] {
        let data = Data(item.payloadJSON.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard var dictionary = object as? [String: Any] else {
            return ["recordName": item.recordName.uuidString.lowercased()]
        }
        dictionary.removeValue(forKey: "eventIdentifier")
        dictionary.removeValue(forKey: "calendarIdentifier")
        if item.recordType == "CDCountdownPreferences" {
            dictionary.removeValue(forKey: "untrackedCalendarIdentifiers")
            dictionary.removeValue(forKey: "hiddenCalendarIdentifiers")
        }
        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = "\(pair.value)"
        }
    }
}
