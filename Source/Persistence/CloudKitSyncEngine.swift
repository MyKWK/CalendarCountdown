import CalendarCountdownCore
import CloudKit
import CryptoKit
import Foundation
import GRDB
import Security

public final class CloudKitSyncEngine: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
    public static let zone = CKRecordZone(zoneName: CloudKitSchema.zoneName)

    public static var hasRequiredContainerEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return value.contains(ProductConstants.cloudKitContainerIdentifier)
    }

    private static func entitledContainer() throws -> CKContainer {
        guard hasRequiredContainerEntitlement else {
            throw DomainError(
                code: .icloudUnavailable,
                message: "当前安装包没有 iCloud 容器权限，已保留本机数据并停用 iCloud 同步。"
            )
        }
        return CKContainer(identifier: ProductConstants.cloudKitContainerIdentifier)
    }

    private var storedWorkspace: Workspace
    private let automaticallySync: Bool
    private let transport: (any CloudSyncTransporting)?
    private var engine: CKSyncEngine?
    public let profileSession: CloudProfileSession
    public var onDidApplyChanges: (@Sendable () -> Void)?
    public var onWorkspaceChanged: (@Sendable (Workspace) -> Void)?
    private var fetchApplyFailedThisCycle = false

    public var workspace: Workspace {
        profileSession.workspace
    }

    public init(
        workspace: Workspace,
        automaticallySync: Bool = true,
        profileSession: CloudProfileSession,
        transport: (any CloudSyncTransporting)? = nil
    ) {
        self.storedWorkspace = workspace
        self.automaticallySync = automaticallySync
        self.profileSession = profileSession
        self.transport = transport
        super.init()
        let previous = self.profileSession.onWorkspaceChanged
        self.profileSession.onWorkspaceChanged = { [weak self] newWorkspace in
            previous?(newWorkspace)
            self?.storedWorkspace = newWorkspace
            self?.onWorkspaceChanged?(newWorkspace)
        }
    }

    public func restartAfterProfileChange() {
        DiagnosticLogger.shared.log(.notice, category: .sync, event: "sync.profile_restart.requested")
        engine = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try self.start()
                _ = try await self.syncNow()
            } catch {
                DiagnosticLogger.shared.log(
                    .error,
                    category: .sync,
                    event: "sync.profile_restart.failed",
                    metadata: DiagnosticLogger.errorMetadata(error)
                )
            }
        }
    }

    @discardableResult
    public func start() throws -> CKSyncEngine {
        if let engine {
            DiagnosticLogger.shared.log(.debug, category: .sync, event: "sync.engine.reused")
            return engine
        }
        do {
            let container = try Self.entitledContainer()
            let serialization = try loadSerialization()
            var configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: serialization,
                delegate: self
            )
            configuration.automaticallySync = automaticallySync
            let engine = CKSyncEngine(configuration)
            self.engine = engine
            engine.state.add(pendingDatabaseChanges: [.saveZone(Self.zone)])
            try enqueueOutbox(into: engine)
            DiagnosticLogger.shared.log(
                .notice,
                category: .sync,
                event: "sync.engine.started",
                metadata: [
                    "automatic": String(automaticallySync),
                    "restored_state": String(serialization != nil),
                    "zone": Self.zone.zoneID.zoneName
                ]
            )
            Task {
                await refreshAccountStatus()
            }
            return engine
        } catch {
            DiagnosticLogger.shared.log(
                .fault,
                category: .sync,
                event: "sync.engine.start_failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            throw error
        }
    }

    public func syncNow() async throws -> CloudSyncStatus {
        let cycleID = UUID()
        let started = Date()
        do {
            guard try workspace.cloud.mode() == .iCloud else {
                let status = try workspace.cloud.status()
                DiagnosticLogger.shared.log(
                    .info,
                    category: .sync,
                    event: "sync.cycle.skipped_local_only",
                    correlationID: cycleID,
                    metadata: ["pending_outbox": String(status.pendingOutbox)]
                )
                return status
            }
            let before = try workspace.cloud.status()
            DiagnosticLogger.shared.log(
                .notice,
                category: .sync,
                event: "sync.cycle.started",
                correlationID: cycleID,
                metadata: [
                    "pending_outbox": String(before.pendingOutbox),
                    "pending_inbox": String(before.pendingInbox),
                    "open_conflicts": String(before.openConflicts)
                ]
            )
            fetchApplyFailedThisCycle = false
            let sendAt: Date
            if let transport {
                try await transport.sendChanges()
                sendAt = Date()
                try await transport.fetchChanges()
            } else {
                let engine = try start()
                await refreshAccountStatus()
                try enqueueOutbox(into: engine)
                try await engine.sendChanges()
                sendAt = Date()
                try await engine.fetchChanges()
            }
            try persistCycleTimestamps(lastSendAt: sendAt)
            let status = try workspace.cloud.status()
            DiagnosticLogger.shared.log(
                .notice,
                category: .sync,
                event: "sync.cycle.completed",
                correlationID: cycleID,
                metadata: [
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                    "pending_outbox": String(status.pendingOutbox),
                    "pending_inbox": String(status.pendingInbox),
                    "open_conflicts": String(status.openConflicts),
                    "account_status": status.account.rawValue
                ]
            )
            return status
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .sync,
                event: "sync.cycle.failed",
                correlationID: cycleID,
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000))
                ]) { current, _ in current }
            )
            throw error
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case let .stateUpdate(update):
            do {
                try workspace.cloud.persistSerializedState(
                    try encodeSerialization(update.stateSerialization),
                    accountHash: nil
                )
            } catch {
                DiagnosticLogger.shared.log(
                    .error,
                    category: .sync,
                    event: "sync.state.persist_failed",
                    metadata: DiagnosticLogger.errorMetadata(error)
                )
            }
        case let .accountChange(change):
            await handleAccountChange(change)
        case let .fetchedRecordZoneChanges(fetched):
            applyFetched(fetched)
        case let .sentRecordZoneChanges(sent):
            handleSent(sent, syncEngine: syncEngine)
        case .fetchedDatabaseChanges, .sentDatabaseChanges,
             .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges,
             .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard (try? workspace.cloud.mode()) == .iCloud else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        let envelopes = (try? workspace.cloud.exportPending(ack: false).records) ?? []
        let byName = Dictionary(uniqueKeysWithValues: envelopes.map {
            ($0.recordName.uuidString.lowercased(), $0)
        })
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let envelope = byName[recordID.recordName.lowercased()] else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return Self.makeRecord(envelope)
        }
    }

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) async {
        DiagnosticLogger.shared.log(
            .notice,
            category: .sync,
            event: "sync.account.changed",
            metadata: ["change_type": String(describing: event.changeType)]
        )
        switch event.changeType {
        case .signIn:
            await refreshAccountStatus()
            if let hash = try? workspace.cloud.status().accountIdentifierHash {
                let switched = try? profileSession.activateAccount(hash: hash)
                if switched?.didChangeDatabase == true {
                    engine = nil
                }
            }
            try? workspace.cloud.setMode(.iCloud)
            if let engine = try? start() {
                engine.state.add(pendingDatabaseChanges: [.saveZone(Self.zone)])
                try? enqueueOutbox(into: engine)
            }
        case .signOut:
            try? workspace.cloud.setMode(.localOnly)
            try? workspace.cloud.setAccountStatus(.signedOut)
            _ = try? profileSession.lockCurrentAccount()
            engine = nil
        case .switchAccounts:
            _ = try? profileSession.lockCurrentAccount()
            engine = nil
            await refreshAccountStatus()
            if let hash = try? workspace.cloud.status().accountIdentifierHash {
                _ = try? profileSession.activateAccount(hash: hash)
                try? workspace.cloud.setMode(.iCloud)
                restartAfterProfileChange()
            }
        @unknown default:
            try? workspace.cloud.setAccountStatus(.unknown)
        }
    }

    func applyFetchedForTesting(envelopes: [CloudRecordEnvelope], decodeFailed: Int = 0) {
        applyFetchedEnvelopes(envelopes, decodeFailed: decodeFailed, remoteDeviceIDs: [])
    }

    private func persistCycleTimestamps(lastSendAt: Date) throws {
        try workspace.cloud.persistSerializedState(
            nil,
            accountHash: try workspace.cloud.status().accountIdentifierHash,
            lastFetchAt: fetchApplyFailedThisCycle ? nil : Date(),
            lastSendAt: lastSendAt
        )
    }

    private func applyFetched(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var envelopes: [CloudRecordEnvelope] = []
        var remoteDeviceIDs = Set<String>()
        var decodeFailed = 0
        for modification in event.modifications {
            if let envelope = Self.envelope(from: modification.record) {
                envelopes.append(envelope)
                remoteDeviceIDs.insert(envelope.modifiedByDevice.uuidString.lowercased())
            } else {
                decodeFailed += 1
            }
        }
        for deletion in event.deletions {
            if let id = UUID(uuidString: deletion.recordID.recordName) {
                envelopes.append(
                    CloudRecordEnvelope(
                        recordType: deletion.recordType,
                        recordName: id,
                        operation: "delete",
                        revision: 0,
                        payloadJSON: "{}",
                        modifiedByDevice: UUID(),
                        updatedAt: Date(),
                        deletedAt: Date()
                    )
                )
            } else {
                decodeFailed += 1
            }
        }
        applyFetchedEnvelopes(envelopes, decodeFailed: decodeFailed, remoteDeviceIDs: remoteDeviceIDs)
    }

    private func applyFetchedEnvelopes(
        _ envelopes: [CloudRecordEnvelope],
        decodeFailed: Int,
        remoteDeviceIDs: Set<String>
    ) {
        guard (try? workspace.cloud.mode()) == .iCloud else {
            DiagnosticLogger.shared.log(.debug, category: .sync, event: "sync.fetch.ignored_local_only")
            return
        }
        do {
            if envelopes.isEmpty, decodeFailed == 0 {
                try workspace.cloud.persistSerializedState(nil, accountHash: nil, lastFetchAt: Date())
                DiagnosticLogger.shared.log(.debug, category: .sync, event: "sync.fetch.empty")
                return
            }
            let report = try workspace.cloud.ingestFetched(envelopes, advanceFetchCursor: decodeFailed == 0)
            DiagnosticLogger.shared.log(
                decodeFailed > 0 || report.failed > 0 ? .warning : .notice,
                category: .sync,
                event: "sync.fetch.applied",
                metadata: [
                    "received": String(envelopes.count),
                    "applied": String(report.applied),
                    "created": String(report.created),
                    "updated": String(report.updated),
                    "conflicts": String(report.conflicts),
                    "failed": String(report.failed),
                    "decode_failed": String(decodeFailed),
                    // CloudKit deletions do not carry our source-device field, so only
                    // attribute fetched modifications to devices we can actually prove.
                    "remote_device_ids": remoteDeviceIDs.sorted().joined(separator: ","),
                    "record_types": Set(envelopes.map(\.recordType)).sorted().joined(separator: ",")
                ]
            )
            if decodeFailed > 0 || report.failed > 0 {
                fetchApplyFailedThisCycle = true
                return
            }
            if report.applied > 0 {
                onDidApplyChanges?()
            }
        } catch {
            fetchApplyFailedThisCycle = true
            DiagnosticLogger.shared.log(
                .error,
                category: .sync,
                event: "sync.fetch.apply_failed",
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "received": String(envelopes.count),
                    "decode_failed": String(decodeFailed)
                ]) { current, _ in current }
            )
        }
    }

    private func handleSent(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        let savedNames = Set(event.savedRecords.map { $0.recordID.recordName.lowercased() })
        if !savedNames.isEmpty {
            do {
                try workspace.db.write { db in
                    let rows = try CloudOutboxRow.fetchAll(db)
                    let ids = rows.filter { savedNames.contains($0.recordName.lowercased()) }.map(\.id)
                    try DomainWriter.ackOutbox(db, ids: ids)
                }
            } catch {
                DiagnosticLogger.shared.log(
                    .error,
                    category: .sync,
                    event: "sync.send.ack_failed",
                    metadata: DiagnosticLogger.errorMetadata(error).merging([
                        "saved": String(savedNames.count)
                    ]) { current, _ in current }
                )
            }
        }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var zoneRetry: [CKSyncEngine.PendingDatabaseChange] = []
        for failure in event.failedRecordSaves {
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord, let remote = Self.envelope(from: server) {
                    _ = try? workspace.cloud.apply([remote])
                    retry.append(.saveRecord(failure.record.recordID))
                }
            case .zoneNotFound:
                zoneRetry.append(.saveZone(Self.zone))
                retry.append(.saveRecord(failure.record.recordID))
            case .unknownItem:
                retry.append(.saveRecord(failure.record.recordID))
            default:
                break
            }
        }
        syncEngine.state.add(pendingDatabaseChanges: zoneRetry)
        syncEngine.state.add(pendingRecordZoneChanges: retry)
        do {
            try workspace.cloud.persistSerializedState(nil, accountHash: nil, lastSendAt: Date())
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .sync,
                event: "sync.send.state_persist_failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
        }
        DiagnosticLogger.shared.log(
            event.failedRecordSaves.isEmpty ? .notice : .warning,
            category: .sync,
            event: "sync.send.completed",
            metadata: [
                "saved": String(savedNames.count),
                "failed": String(event.failedRecordSaves.count),
                "record_retries": String(retry.count),
                "zone_retries": String(zoneRetry.count)
            ]
        )
    }

    private func enqueueOutbox(into engine: CKSyncEngine) throws {
        guard try workspace.cloud.mode() == .iCloud else { return }
        let bundle = try workspace.cloud.exportPending(ack: false)
        let changes: [CKSyncEngine.PendingRecordZoneChange] = bundle.records.map { envelope in
            .saveRecord(Self.recordID(for: envelope.recordName))
        }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
        DiagnosticLogger.shared.log(
            .debug,
            category: .sync,
            event: "sync.outbox.enqueued",
            metadata: ["record_count": String(changes.count)]
        )
    }

    private func refreshAccountStatus() async {
        do {
            let container = try Self.entitledContainer()
            let status = try await container.accountStatus()
            let mapped: CloudAccountStatus
            switch status {
            case .available: mapped = .available
            case .noAccount: mapped = .noAccount
            case .restricted: mapped = .restricted
            case .couldNotDetermine: mapped = .couldNotDetermine
            case .temporarilyUnavailable: mapped = .temporarilyUnavailable
            @unknown default: mapped = .unknown
            }
            try workspace.cloud.setAccountStatus(mapped)
            if status == .available, let recordName = try? await container.userRecordID().recordName {
                let hash = SHA256.hash(data: Data(recordName.utf8)).map { String(format: "%02x", $0) }.joined()
                try workspace.cloud.persistSerializedState(nil, accountHash: String(hash.prefix(16)))
            }
            DiagnosticLogger.shared.log(
                .info,
                category: .sync,
                event: "sync.account.status",
                metadata: ["status": mapped.rawValue]
            )
        } catch {
            try? workspace.cloud.setAccountStatus(.couldNotDetermine)
            DiagnosticLogger.shared.log(
                .warning,
                category: .sync,
                event: "sync.account.status_failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
        }
    }

    private func loadSerialization() throws -> CKSyncEngine.State.Serialization? {
        guard let data = try workspace.cloud.serializedState() else { return nil }
        return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func encodeSerialization(_ value: CKSyncEngine.State.Serialization) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private static func recordID(for name: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: name.uuidString.lowercased(), zoneID: zone.zoneID)
    }

    static func makeRecord(_ envelope: CloudRecordEnvelope) -> CKRecord {
        let record = CKRecord(recordType: envelope.recordType, recordID: recordID(for: envelope.recordName))
        record["payloadJSON"] = envelope.payloadJSON
        record["revision"] = envelope.revision
        record["operation"] = envelope.operation
        record["modifiedByDevice"] = envelope.modifiedByDevice.uuidString.lowercased()
        record["updatedAt"] = envelope.updatedAt
        record["deletedAt"] = envelope.deletedAt
        if let fields = try? JSONCoding.encoder(pretty: false).encode(envelope.fields),
           let text = String(data: fields, encoding: .utf8) {
            record["fieldsJSON"] = text
        }
        return record
    }

    static func envelope(from record: CKRecord) -> CloudRecordEnvelope? {
        guard let name = UUID(uuidString: record.recordID.recordName) else { return nil }
        let payload = record["payloadJSON"] as? String ?? "{}"
        let revision = (record["revision"] as? Int64) ?? Int64((record["revision"] as? Int) ?? 0)
        let operation = record["operation"] as? String ?? "upsert"
        let device = (record["modifiedByDevice"] as? String).flatMap(UUID.init) ?? UUID()
        let updated = record["updatedAt"] as? Date ?? Date()
        let deleted = record["deletedAt"] as? Date
        let fields: [String: CloudFieldSnapshot]
        if let text = record["fieldsJSON"] as? String,
           let decoded = try? JSONCoding.decoder().decode([String: CloudFieldSnapshot].self, from: Data(text.utf8)) {
            fields = decoded
        } else {
            fields = [:]
        }
        return CloudRecordEnvelope(
            recordType: record.recordType,
            recordName: name,
            operation: operation,
            revision: revision,
            payloadJSON: payload,
            fields: fields,
            modifiedByDevice: device,
            updatedAt: updated,
            deletedAt: deleted
        )
    }
}
