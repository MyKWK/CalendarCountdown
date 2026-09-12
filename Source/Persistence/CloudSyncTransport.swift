import Foundation

public protocol CloudSyncTransporting: Sendable {
    func sendChanges() async throws
    func fetchChanges() async throws
}

public final class FakeCloudSyncTransport: CloudSyncTransporting, @unchecked Sendable {
    public var sendHandler: (@Sendable () async throws -> Void)?
    public var fetchHandler: (@Sendable () async throws -> Void)?
    public private(set) var sendCount = 0
    public private(set) var fetchCount = 0

    public init(
        sendHandler: (@Sendable () async throws -> Void)? = nil,
        fetchHandler: (@Sendable () async throws -> Void)? = nil
    ) {
        self.sendHandler = sendHandler
        self.fetchHandler = fetchHandler
    }

    public func sendChanges() async throws {
        sendCount += 1
        try await sendHandler?()
    }

    public func fetchChanges() async throws {
        fetchCount += 1
        try await fetchHandler?()
    }
}
