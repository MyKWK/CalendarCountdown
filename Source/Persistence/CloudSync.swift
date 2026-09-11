import CalendarCountdownCore
import Foundation
import GRDB

public struct CloudSyncService: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func mode() throws -> CloudSyncMode {
        try db.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM local_kv WHERE key = ?",
                arguments: ["cloud_mode"]
            )
            return CloudSyncMode(rawValue: value ?? "") ?? .localOnly
        }
    }

    public func setMode(_ mode: CloudSyncMode) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_kv(key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: ["cloud_mode", mode.rawValue]
            )
        }
    }

    public func accountStatus() throws -> CloudAccountStatus {
        try db.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM local_kv WHERE key = ?",
                arguments: ["cloud_account_status"]
            )
            return CloudAccountStatus(rawValue: value ?? "") ?? .unknown
        }
    }

    public func setAccountStatus(_ status: CloudAccountStatus) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_kv(key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: ["cloud_account_status", status.rawValue]
            )
        }
    }

    public func status() throws -> CloudSyncStatus {
        try db.read { db in
            let pending = try CloudOutboxRow.fetchCount(db)
            let conflicts = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM merge_conflicts WHERE resolved_at IS NULL"
            ) ?? 0
            let state = try CloudSyncStateRow.fetchOne(db, key: "private")
            return CloudSyncStatus(
                mode: CloudSyncMode(rawValue: (try String.fetchOne(
                    db,
                    sql: "SELECT value FROM local_kv WHERE key = ?",
                    arguments: ["cloud_mode"]
                )) ?? "") ?? .localOnly,
                account: CloudAccountStatus(rawValue: (try String.fetchOne(
                    db,
                    sql: "SELECT value FROM local_kv WHERE key = ?",
                    arguments: ["cloud_account_status"]
                )) ?? "") ?? .unknown,
                pendingOutbox: pending,
                openConflicts: conflicts,
                lastFetchAt: try SQLValue.date(state?.lastFetchAt),
                lastSendAt: try SQLValue.date(state?.lastSendAt),
                hasSerializedState: state?.ckStateSerialization != nil,
                accountIdentifierHash: state?.accountIdentifierHash,
                pendingInbox: try CloudInboxRow.fetchCount(db)
            )
        }
    }

    public func serializedState() throws -> Data? {
        try db.read { db in
            try CloudSyncStateRow.fetchOne(db, key: "private")?.ckStateSerialization
        }
    }

    public func persistSerializedState(
        _ data: Data?,
        accountHash: String?,
        lastFetchAt: Date? = nil,
        lastSendAt: Date? = nil
    ) throws {
        try db.write { db in
            var row = try CloudSyncStateRow.fetchOne(db, key: "private") ?? CloudSyncStateRow(
                scope: "private",
                ckStateSerialization: nil,
                accountIdentifierHash: nil,
                lastFetchAt: nil,
                lastSendAt: nil
            )
            row.ckStateSerialization = data ?? row.ckStateSerialization
            if let accountHash {
                row.accountIdentifierHash = accountHash
            }
            if let lastFetchAt {
                row.lastFetchAt = RFC3339.utcString(from: lastFetchAt)
            }
            if let lastSendAt {
                row.lastSendAt = RFC3339.utcString(from: lastSendAt)
            }
            try row.save(db)
        }
    }

    public func exportPending(ack: Bool = false) throws -> CloudBundle {
        try exportPendingDetailed(ack: ack).bundle
    }

    public func exportPendingDetailed(ack: Bool = false) throws -> (bundle: CloudBundle, report: CloudExportReport) {
        let prepared = try db.read { db in
            try CloudSyncApplicator.envelopes(fromOutbox: db)
        }
        if ack {
            try db.write { db in
                try DomainWriter.ackOutbox(db, ids: prepared.exportedIDs)
            }
        }
        return (
            CloudBundle(records: prepared.records),
            CloudExportReport(
                recordCount: prepared.records.count,
                acked: ack ? prepared.exportedIDs.count : 0,
                skipped: prepared.skipped,
                outboxIDs: prepared.exportedIDs
            )
        )
    }

    public func apply(_ bundle: CloudBundle) throws -> CloudApplyReport {
        try apply(bundle.records)
    }

    public func apply(_ records: [CloudRecordEnvelope]) throws -> CloudApplyReport {
        let deviceID = db.deviceID
        return try db.write { db in
            try CloudSyncApplicator.apply(records, db: db, deviceID: deviceID)
        }
    }

    public func ingestFetched(
        _ records: [CloudRecordEnvelope],
        fetchedAt: Date = Date(),
        advanceFetchCursor: Bool = true
    ) throws -> CloudApplyReport {
        try persistInbox(records, receivedAt: fetchedAt)
        var report = try replayInbox()
        report.pendingInbox = try inboxCount()
        if advanceFetchCursor && report.failed == 0 {
            try persistSerializedState(nil, accountHash: nil, lastFetchAt: fetchedAt)
            report.lastFetchAdvanced = true
        }
        if report.applied > 0 {
            NotificationCenter.default.post(name: .calendarCountdownCloudDidApply, object: nil)
        }
        return report
    }

    public func replayInbox() throws -> CloudApplyReport {
        let deviceID = db.deviceID
        return try db.write { db in
            try CloudSyncApplicator.replayInbox(db: db, deviceID: deviceID)
        }
    }

    public func inboxCount() throws -> Int {
        try db.read { db in try CloudInboxRow.fetchCount(db) }
    }

    public func persistInbox(_ records: [CloudRecordEnvelope], receivedAt: Date = Date()) throws {
        guard !records.isEmpty else { return }
        try db.write { db in
            try CloudSyncApplicator.persistInbox(records, db: db, receivedAt: receivedAt)
        }
    }

    public func pendingSagaCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pending_operations WHERE stage = 'projection'"
            ) ?? 0
        }
    }
}

enum CloudSyncApplicator {
    struct PreparedExport {
        var records: [CloudRecordEnvelope]
        var exportedIDs: [String]
        var skipped: Int
    }

    static func envelopes(fromOutbox db: Database) throws -> PreparedExport {
        let rows = try CloudOutboxRow.order(sql: "enqueued_at ASC").fetchAll(db)
        var records: [CloudRecordEnvelope] = []
        var exportedIDs: [String] = []
        var skipped = 0
        for row in rows {
            if let envelope = try envelope(from: row, db: db) {
                records.append(envelope)
                exportedIDs.append(row.id)
            } else {
                skipped += 1
            }
        }
        return PreparedExport(records: records, exportedIDs: exportedIDs, skipped: skipped)
    }

    static func apply(
        _ records: [CloudRecordEnvelope],
        db: Database,
        deviceID _: UUID
    ) throws -> CloudApplyReport {
        var report = CloudApplyReport()
        let ordered = records.sorted { lhs, rhs in
            let left = CloudKitSchema.applyOrder.firstIndex(of: lhs.recordType) ?? 99
            let right = CloudKitSchema.applyOrder.firstIndex(of: rhs.recordType) ?? 99
            if left != right { return left < right }
            return lhs.updatedAt < rhs.updatedAt
        }
        for record in ordered {
            do {
                let outcome = try applyOne(record, db: db)
                switch outcome {
                case .created:
                    report.applied += 1
                    report.created += 1
                case .updated:
                    report.applied += 1
                    report.updated += 1
                case .conflict(let summary):
                    report.applied += 1
                    report.updated += 1
                    report.conflicts += 1
                    report.conflictSummaries.append(summary)
                case .skipped:
                    report.skipped += 1
                }
            } catch {
                report.failed += 1
                report.conflictSummaries.append("\(record.recordType) \(record.recordName.uuidString.lowercased()): \(error.localizedDescription)")
            }
        }
        return report
    }

    static func persistInbox(
        _ records: [CloudRecordEnvelope],
        db: Database,
        receivedAt: Date
    ) throws {
        for record in records {
            try db.execute(
                sql: "DELETE FROM cloud_inbox WHERE record_type = ? AND record_name = ?",
                arguments: [record.recordType, SQLValue.uuid(record.recordName)]
            )
            let row = CloudInboxRow(
                id: SQLValue.uuid(record.id),
                recordType: record.recordType,
                recordName: SQLValue.uuid(record.recordName),
                operation: record.operation,
                revision: record.revision,
                payloadJson: record.payloadJSON,
                fieldsJson: record.fields.isEmpty ? nil : try SQLValue.json(record.fields),
                modifiedByDevice: SQLValue.uuid(record.modifiedByDevice),
                updatedAt: RFC3339.utcString(from: record.updatedAt),
                deletedAt: SQLValue.date(record.deletedAt),
                receivedAt: RFC3339.utcString(from: receivedAt),
                retryCount: 0,
                lastError: nil,
                status: "pending"
            )
            try row.insert(db)
        }
    }

    static func replayInbox(db: Database, deviceID _: UUID) throws -> CloudApplyReport {
        let rows = try CloudInboxRow.fetchAll(db)
        let pairs: [(CloudInboxRow, CloudRecordEnvelope)] = try rows.map { row in
            (row, try envelope(from: row))
        }
        let ordered = pairs.sorted { lhs, rhs in
            let left = CloudKitSchema.applyOrder.firstIndex(of: lhs.1.recordType) ?? 99
            let right = CloudKitSchema.applyOrder.firstIndex(of: rhs.1.recordType) ?? 99
            if left != right { return left < right }
            return lhs.1.updatedAt < rhs.1.updatedAt
        }
        var report = CloudApplyReport()
        for (row, record) in ordered {
            do {
                let outcome = try applyOne(record, db: db)
                switch outcome {
                case .created:
                    try row.delete(db)
                    report.applied += 1
                    report.created += 1
                case .updated:
                    try row.delete(db)
                    report.applied += 1
                    report.updated += 1
                case .conflict(let summary):
                    try row.delete(db)
                    report.applied += 1
                    report.updated += 1
                    report.conflicts += 1
                    report.conflictSummaries.append(summary)
                case .skipped:
                    try db.execute(
                        sql: """
                            UPDATE cloud_inbox
                            SET status = 'deferred', retry_count = retry_count + 1, last_error = ?
                            WHERE id = ?
                            """,
                        arguments: ["missing_parent", row.id]
                    )
                    report.skipped += 1
                }
            } catch {
                try db.execute(
                    sql: """
                        UPDATE cloud_inbox
                        SET status = 'failed', retry_count = retry_count + 1, last_error = ?
                        WHERE id = ?
                        """,
                    arguments: [error.localizedDescription, row.id]
                )
                report.failed += 1
                report.conflictSummaries.append("\(record.recordType) \(record.recordName.uuidString.lowercased()): \(error.localizedDescription)")
            }
        }
        return report
    }

    private static func envelope(from row: CloudInboxRow) throws -> CloudRecordEnvelope {
        let fields = try SQLValue.json([String: CloudFieldSnapshot].self, row.fieldsJson) ?? [:]
        return CloudRecordEnvelope(
            recordType: row.recordType,
            recordName: try SQLValue.uuid(row.recordName),
            operation: row.operation,
            revision: row.revision,
            payloadJSON: row.payloadJson,
            fields: fields,
            modifiedByDevice: try SQLValue.uuid(row.modifiedByDevice),
            updatedAt: try SQLValue.requiredDate(row.updatedAt),
            deletedAt: try SQLValue.date(row.deletedAt)
        )
    }

    private enum Outcome {
        case created
        case updated
        case conflict(String)
        case skipped
    }

    private static func applyOne(
        _ record: CloudRecordEnvelope,
        db: Database
    ) throws -> Outcome {
        switch record.recordType {
        case "CDMission":
            return try applyMission(record, db: db)
        case "CDTaskSeries":
            return try applySeries(record, db: db)
        case "CDTaskOccurrence":
            return try applyOccurrence(record, db: db)
        case "CDHabit":
            return try applyHabit(record, db: db)
        case "CDHabitPeriod":
            return try applyHabitPeriod(record, db: db)
        case "CDCheckIn":
            return try applyCheckIn(record, db: db)
        case "CDProjectionSettings":
            return try applySettings(record, db: db)
        case "CDManagedEvent":
            return try applyManagedEvent(record, db: db)
        case "CDCountdownSelection":
            return try applyCountdownSelection(record, db: db)
        case "CDCountdownPreferences":
            return try applyCountdownPreferences(record, db: db)
        default:
            return .skipped
        }
    }

    private static func applyManagedEvent(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(
            CountdownManagedCloudPayload.self,
            from: Data(record.payloadJSON.utf8)
        )
        var merged = ManagedEventRecord(
            id: remote.id,
            draft: remote.draft,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            revision: remote.revision,
            modifiedByDevice: remote.modifiedByDevice,
            deletedAt: remote.deletedAt
        )
        if let local = try DomainQueries.managedEventIncludingDeleted(db, id: remote.id) {
            if merged.draft.calendarIdentifier == nil {
                merged.draft.calendarIdentifier = local.draft.calendarIdentifier
            }
            if record.operation == "delete" || remote.deletedAt != nil {
                merged.deletedAt = remote.deletedAt ?? remote.updatedAt
            }
            try ManagedEventRow(merged).save(db)
            return .updated
        }
        try ManagedEventRow(merged).save(db)
        return .created
    }

    private static func applyCountdownSelection(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(
            CountdownSelectionCloudPayload.self,
            from: Data(record.payloadJSON.utf8)
        )
        let local = try DomainQueries.countdownSelection(db, id: remote.id, includingDeleted: true)
        var selection = CountdownSelection(
            id: remote.id,
            mode: remote.mode,
            calendarIdentifier: local?.calendarIdentifier,
            calendarTitle: remote.calendarTitle,
            eventIdentifier: local?.eventIdentifier,
            externalIdentifier: remote.externalIdentifier,
            managedRecordID: remote.managedRecordID,
            eventTitle: remote.eventTitle,
            occurrenceDate: remote.occurrenceDate,
            selectedAt: remote.selectedAt,
            updatedAt: remote.updatedAt,
            revision: remote.revision,
            modifiedByDevice: remote.modifiedByDevice,
            deletedAt: remote.deletedAt
        )
        if record.operation == "delete" {
            selection.deletedAt = remote.deletedAt ?? remote.updatedAt
        }
        try CountdownSelectionRow(selection).save(db)
        return local == nil ? .created : .updated
    }

    private static func applyCountdownPreferences(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(
            CountdownPreferencesCloudPayload.self,
            from: Data(record.payloadJSON.utf8)
        )
        let existed = try CountdownPreferencesRow.fetchOne(db, key: SQLValue.uuid(remote.id)) != nil
        let row = CountdownPreferencesRow(
            id: SQLValue.uuid(remote.id),
            pinnedSelectionId: remote.pinnedSelectionID.map(SQLValue.uuid),
            revision: remote.revision,
            updatedAt: RFC3339.utcString(from: remote.updatedAt),
            modifiedByDevice: SQLValue.uuid(remote.modifiedByDevice)
        )
        try row.save(db)
        return existed ? .updated : .created
    }

    private static func applyMission(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(MissionDefinition.self, from: Data(record.payloadJSON.utf8))
        guard var local = try DomainQueries.mission(db, id: remote.id) else {
            try MissionRow(remote).insert(db)
            try persistIncomingFields(recordWithMissionFields(record, mission: remote), objectType: "mission", db: db)
            return .created
        }
        if record.operation == "delete" || remote.deletedAt != nil {
            if local.deletedAt == nil || (remote.deletedAt ?? remote.updatedAt) >= (local.deletedAt ?? local.updatedAt) {
                local.deletedAt = remote.deletedAt ?? remote.updatedAt
                local.updatedAt = remote.updatedAt
                local.revision = max(local.revision, remote.revision)
                try MissionRow(local).update(db)
            }
            try persistIncomingFields(record, objectType: "mission", db: db)
            return .updated
        }
        if local.deletedAt != nil, (local.deletedAt ?? local.updatedAt) >= remote.updatedAt {
            return .skipped
        }
        let client = try currentMissionSnapshots(local, db: db)
        let ancestor = try DomainWriter.ancestorSnapshots(db, objectType: "mission", objectID: local.id)
        let server = missionFieldSnapshots(record, mission: remote)
        let merged = CloudMergePolicy.merge(
            ancestor: ancestor,
            server: server,
            client: client
        )
        if let title = merged.fields["title"] ?? nil { local.title = title }
        if merged.fields.keys.contains("description_md") {
            local.markdownDescription = merged.fields["description_md"] ?? nil
        }
        if let status = merged.fields["status"] ?? nil {
            local.status = MissionStatus(rawValue: status) ?? local.status
        }
        local.color = remote.color
        local.icon = remote.icon
        local.targetDate = remote.targetDate
        local.updatedAt = max(local.updatedAt, remote.updatedAt)
        local.revision = max(local.revision, remote.revision)
        if merged.decisions.values.contains(where: { if case .takeServer = $0 { true } else { false } }) {
            local.modifiedByDevice = remote.modifiedByDevice
        }
        try MissionRow(local).update(db)
        try persistMergeOutcome(
            merged,
            remote: record,
            server: server,
            client: client,
            objectType: "mission",
            objectID: local.id,
            db: db
        )
        if merged.hasUnresolvedConflict {
            try recordConflicts(merged, objectType: "mission", objectID: local.id, db: db)
            return .conflict("mission \(local.id.uuidString.lowercased()) markdown")
        }
        return .updated
    }

    private static func applySeries(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(TaskSeries.self, from: Data(record.payloadJSON.utf8))
        if record.operation == "delete" || remote.deletedAt != nil {
            if var local = try DomainQueries.series(db, id: remote.id) {
                local.deletedAt = remote.deletedAt ?? remote.updatedAt
                local.updatedAt = remote.updatedAt
                local.revision = max(local.revision, remote.revision)
                try TaskSeriesRow(local).update(db)
                return .updated
            }
            try TaskSeriesRow(remote).insert(db)
            return .created
        }
        if let missionID = remote.missionID, try DomainQueries.mission(db, id: missionID) == nil {
            return .skipped
        }
        if let local = try DomainQueries.series(db, id: remote.id) {
            if local.deletedAt != nil, (local.deletedAt ?? local.updatedAt) >= remote.updatedAt {
                return .skipped
            }
            if local.revision > remote.revision {
                return .skipped
            }
        }
        let existed = try DomainQueries.series(db, id: remote.id) != nil
        try TaskSeriesRow(remote).save(db)
        try persistIncomingFields(record, objectType: "task_series", db: db)
        return existed ? .updated : .created
    }

    private static func applyOccurrence(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(TaskOccurrence.self, from: Data(record.payloadJSON.utf8))
        if record.operation == "delete" || remote.deletedAt != nil {
            if var local = try DomainQueries.occurrenceIncludingDeleted(db, id: remote.id) {
                local.deletedAt = remote.deletedAt ?? remote.updatedAt
                local.updatedAt = remote.updatedAt
                local.revision = max(local.revision, remote.revision)
                try TaskOccurrenceRow(local).update(db)
                return .updated
            }
            guard try DomainQueries.series(db, id: remote.seriesID) != nil else { return .skipped }
            try TaskOccurrenceRow(remote).insert(db)
            return .created
        }
        guard try DomainQueries.series(db, id: remote.seriesID) != nil else { return .skipped }
        if let local = try DomainQueries.occurrenceIncludingDeleted(db, id: remote.id) {
            if local.deletedAt != nil, (local.deletedAt ?? local.updatedAt) >= remote.updatedAt {
                return .skipped
            }
            let client = try currentOccurrenceSnapshots(local, db: db)
            let ancestor = try DomainWriter.ancestorSnapshots(db, objectType: "task_occurrence", objectID: local.id)
            let server = occurrenceFieldSnapshots(record, occurrence: remote)
            let merged = CloudMergePolicy.merge(
                ancestor: ancestor,
                server: server,
                client: client
            )
            var next = remote
            if let status = merged.fields["status"] ?? nil {
                next.status = TaskOccurrenceStatus(rawValue: status) ?? remote.status
            }
            if merged.fields.keys.contains("title") {
                next.titleOverride = merged.fields["title"] ?? nil
            }
            next.revision = max(local.revision, remote.revision)
            try TaskOccurrenceRow(next).save(db)
            try persistMergeOutcome(
                merged,
                remote: record,
                server: server,
                client: client,
                objectType: "task_occurrence",
                objectID: local.id,
                db: db
            )
            return merged.hasUnresolvedConflict ? .conflict("occurrence \(local.id.uuidString.lowercased())") : .updated
        }
        try TaskOccurrenceRow(remote).insert(db)
        try persistIncomingFields(record, objectType: "task_occurrence", db: db)
        return .created
    }

    private static func applyHabit(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(HabitDefinition.self, from: Data(record.payloadJSON.utf8))
        if record.operation == "delete" || remote.deletedAt != nil {
            if var local = try DomainQueries.habit(db, id: remote.id) {
                local.deletedAt = remote.deletedAt ?? remote.updatedAt
                local.updatedAt = remote.updatedAt
                local.revision = max(local.revision, remote.revision)
                try HabitRow(local).update(db)
                return .updated
            }
            try HabitRow(remote).insert(db)
            return .created
        }
        let existed = try DomainQueries.habit(db, id: remote.id) != nil
        if let local = try DomainQueries.habit(db, id: remote.id), local.revision > remote.revision {
            return .skipped
        }
        try HabitRow(remote).save(db)
        return existed ? .updated : .created
    }

    private static func applyHabitPeriod(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(HabitPeriod.self, from: Data(record.payloadJSON.utf8))
        guard try DomainQueries.habit(db, id: remote.habitID) != nil else { return .skipped }
        try HabitPeriodRow(remote).save(db)
        return .updated
    }

    private static func applyCheckIn(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(CheckInRecord.self, from: Data(record.payloadJSON.utf8))
        guard try DomainQueries.habit(db, id: remote.habitID) != nil else { return .skipped }
        let existed = try DomainQueries.checkIn(db, id: remote.id) != nil
        try CheckInRow(remote).save(db)
        return existed ? .updated : .created
    }

    private static func applySettings(_ record: CloudRecordEnvelope, db: Database) throws -> Outcome {
        let remote = try JSONCoding.decoder().decode(ProjectionSettings.self, from: Data(record.payloadJSON.utf8))
        try ProjectionSettingsRow(remote).save(db)
        return .updated
    }

    private static func envelope(from row: CloudOutboxRow, db: Database) throws -> CloudRecordEnvelope? {
        let name = try SQLValue.uuid(row.recordName)
        if let payload = row.payloadJson, !payload.isEmpty {
            let fields = try SQLValue.json([String: CloudFieldSnapshot].self, row.fieldsJson) ?? [:]
            let device = try row.modifiedByDevice.map(SQLValue.uuid) ?? UUID()
            let updated = try SQLValue.date(row.updatedAt) ?? Date()
            return CloudRecordEnvelope(
                recordType: row.recordType,
                recordName: name,
                operation: row.operation,
                revision: row.localRevision,
                payloadJSON: payload,
                fields: fields,
                modifiedByDevice: device,
                updatedAt: updated,
                deletedAt: try SQLValue.date(row.deletedAt)
            )
        }
        return try envelope(recordType: row.recordType, recordName: name, operation: row.operation, db: db)
    }

    private static func envelope(
        recordType: String,
        recordName: UUID,
        operation: String,
        db: Database
    ) throws -> CloudRecordEnvelope? {
        switch recordType {
        case "CDMission":
            guard let mission = try DomainQueries.mission(db, id: recordName) else { return nil }
            return CloudRecordEnvelope(
                recordType: recordType,
                recordName: recordName,
                operation: operation,
                revision: mission.revision,
                payloadJSON: try SQLValue.json(mission),
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "mission",
                    objectID: mission.id,
                    values: [
                        "title": mission.title,
                        "description_md": mission.markdownDescription,
                        "status": mission.status.rawValue
                    ],
                    deviceID: mission.modifiedByDevice,
                    now: mission.updatedAt
                ),
                modifiedByDevice: mission.modifiedByDevice,
                updatedAt: mission.updatedAt,
                deletedAt: mission.deletedAt
            )
        case "CDTaskSeries":
            guard let series = try DomainQueries.seriesIncludingDeleted(db, id: recordName) else { return nil }
            return CloudRecordEnvelope(
                recordType: recordType,
                recordName: recordName,
                operation: operation,
                revision: series.revision,
                payloadJSON: try SQLValue.json(series),
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "task_series",
                    objectID: series.id,
                    values: ["title": series.title, "description_md": series.markdownDescription],
                    deviceID: series.modifiedByDevice,
                    now: series.updatedAt
                ),
                modifiedByDevice: series.modifiedByDevice,
                updatedAt: series.updatedAt,
                deletedAt: series.deletedAt
            )
        case "CDTaskOccurrence":
            guard let occurrence = try DomainQueries.occurrenceIncludingDeleted(db, id: recordName) else { return nil }
            return CloudRecordEnvelope(
                recordType: recordType,
                recordName: recordName,
                operation: operation,
                revision: occurrence.revision,
                payloadJSON: try SQLValue.json(occurrence),
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "task_occurrence",
                    objectID: occurrence.id,
                    values: [
                        "status": occurrence.status.rawValue,
                        "title": occurrence.titleOverride
                    ],
                    deviceID: occurrence.modifiedByDevice,
                    now: occurrence.updatedAt
                ),
                modifiedByDevice: occurrence.modifiedByDevice,
                updatedAt: occurrence.updatedAt,
                deletedAt: occurrence.deletedAt
            )
        case "CDHabit":
            guard let habit = try DomainQueries.habit(db, id: recordName) else { return nil }
            return CloudRecordEnvelope(
                recordType: recordType,
                recordName: recordName,
                operation: operation,
                revision: habit.revision,
                payloadJSON: try SQLValue.json(habit),
                fields: [:],
                modifiedByDevice: habit.modifiedByDevice,
                updatedAt: habit.updatedAt,
                deletedAt: habit.deletedAt
            )
        case "CDHabitPeriod":
            let periods = try HabitPeriodRow.fetchAll(db)
            for row in periods {
                let period = try row.domain()
                if CloudRecordIdentity.habitPeriod(habitID: period.habitID, periodKey: period.periodKey) == recordName {
                    return CloudRecordEnvelope(
                        recordType: recordType,
                        recordName: recordName,
                        operation: operation,
                        revision: period.revision,
                        payloadJSON: try SQLValue.json(period),
                        fields: [:],
                        modifiedByDevice: period.modifiedByDevice,
                        updatedAt: period.updatedAt,
                        deletedAt: period.deletedAt
                    )
                }
            }
            return nil
        case "CDCheckIn":
            guard let checkIn = try DomainQueries.checkIn(db, id: recordName) else { return nil }
            return CloudRecordEnvelope(
                recordType: recordType,
                recordName: recordName,
                operation: operation,
                revision: checkIn.revision,
                payloadJSON: try SQLValue.json(checkIn),
                fields: [:],
                modifiedByDevice: checkIn.modifiedByDevice,
                updatedAt: checkIn.updatedAt,
                deletedAt: checkIn.deletedAt
            )
        default:
            return nil
        }
    }

    private static func recordWithMissionFields(
        _ record: CloudRecordEnvelope,
        mission: MissionDefinition
    ) -> CloudRecordEnvelope {
        guard record.fields.isEmpty else { return record }
        var copy = record
        copy.fields = synthesizedMissionFields(mission)
        return copy
    }

    private static func synthesizedMissionFields(_ mission: MissionDefinition) -> [String: CloudFieldSnapshot] {
        let hlc = HybridLogicalTimestamp.now(deviceID: mission.modifiedByDevice, at: mission.updatedAt)
        return [
            "title": CloudFieldSnapshot(value: mission.title, hlc: hlc),
            "description_md": CloudFieldSnapshot(value: mission.markdownDescription, hlc: hlc),
            "status": CloudFieldSnapshot(value: mission.status.rawValue, hlc: hlc)
        ]
    }

    private static func missionFieldSnapshots(
        _ record: CloudRecordEnvelope,
        mission: MissionDefinition
    ) -> [String: FieldSnapshot] {
        let fields = record.fields.isEmpty ? synthesizedMissionFields(mission) : record.fields
        return Dictionary(uniqueKeysWithValues: fields.compactMap { name, payload in
            payload.snapshot().map { (name, $0) }
        })
    }

    private static func occurrenceFieldSnapshots(
        _ record: CloudRecordEnvelope,
        occurrence: TaskOccurrence
    ) -> [String: FieldSnapshot] {
        if !record.fieldSnapshots.isEmpty {
            return record.fieldSnapshots
        }
        let hlc = HybridLogicalTimestamp.now(deviceID: occurrence.modifiedByDevice, at: occurrence.updatedAt)
        return [
            "status": FieldSnapshot(value: occurrence.status.rawValue, hlc: hlc),
            "title": FieldSnapshot(value: occurrence.titleOverride, hlc: hlc)
        ]
    }

    private static func persistMergeOutcome(
        _ merged: RecordMergeResult,
        remote: CloudRecordEnvelope,
        server: [String: FieldSnapshot],
        client: [String: FieldSnapshot],
        objectType: String,
        objectID: UUID,
        db: Database
    ) throws {
        var ancestors: [String: CloudFieldSnapshot] = [:]
        for (name, decision) in merged.decisions {
            switch decision {
            case .takeServer:
                if let field = server[name] {
                    ancestors[name] = CloudFieldSnapshot(value: field.value, hlc: field.hlc)
                    try writeFieldVersion(
                        db,
                        objectType: objectType,
                        objectID: objectID,
                        name: name,
                        hlc: field.hlc.wireValue,
                        deviceID: remote.modifiedByDevice
                    )
                }
            case .takeClient, .unchanged:
                if let field = client[name] {
                    ancestors[name] = CloudFieldSnapshot(value: field.value, hlc: field.hlc)
                }
            case .conflict:
                break
            }
        }
        try DomainWriter.persistAncestors(
            db,
            objectType: objectType,
            objectID: objectID,
            fields: ancestors
        )
    }

    private static func writeFieldVersion(
        _ db: Database,
        objectType: String,
        objectID: UUID,
        name: String,
        hlc: String,
        deviceID: UUID
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO field_versions(object_type, object_id, field_name, hlc, modified_by_device)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(object_type, object_id, field_name)
                DO UPDATE SET hlc = excluded.hlc, modified_by_device = excluded.modified_by_device
                """,
            arguments: [
                objectType,
                SQLValue.uuid(objectID),
                name,
                hlc,
                SQLValue.uuid(deviceID)
            ]
        )
    }

    private static func currentMissionSnapshots(
        _ mission: MissionDefinition,
        db: Database
    ) throws -> [String: FieldSnapshot] {
        let stored = try DomainWriter.fieldSnapshots(
            db,
            objectType: "mission",
            objectID: mission.id,
            values: [
                "title": mission.title,
                "description_md": mission.markdownDescription,
                "status": mission.status.rawValue
            ],
            deviceID: mission.modifiedByDevice,
            now: mission.updatedAt
        )
        return Dictionary(uniqueKeysWithValues: stored.compactMap { name, payload in
            payload.snapshot().map { (name, $0) }
        })
    }

    private static func currentOccurrenceSnapshots(
        _ occurrence: TaskOccurrence,
        db: Database
    ) throws -> [String: FieldSnapshot] {
        let stored = try DomainWriter.fieldSnapshots(
            db,
            objectType: "task_occurrence",
            objectID: occurrence.id,
            values: ["status": occurrence.status.rawValue, "title": occurrence.titleOverride],
            deviceID: occurrence.modifiedByDevice,
            now: occurrence.updatedAt
        )
        return Dictionary(uniqueKeysWithValues: stored.compactMap { name, payload in
            payload.snapshot().map { (name, $0) }
        })
    }

    private static func persistIncomingFields(
        _ record: CloudRecordEnvelope,
        objectType: String,
        db: Database
    ) throws {
        for (name, payload) in record.fields {
            try db.execute(
                sql: """
                    INSERT INTO field_versions(object_type, object_id, field_name, hlc, modified_by_device)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(object_type, object_id, field_name)
                    DO UPDATE SET hlc = excluded.hlc, modified_by_device = excluded.modified_by_device
                    """,
                arguments: [
                    objectType,
                    SQLValue.uuid(record.recordName),
                    name,
                    payload.hlc,
                    SQLValue.uuid(record.modifiedByDevice)
                ]
            )
        }
        try DomainWriter.persistAncestors(
            db,
            objectType: objectType,
            objectID: record.recordName,
            fields: record.fields
        )
    }

    private static func recordConflicts(
        _ merged: RecordMergeResult,
        objectType: String,
        objectID: UUID,
        db: Database
    ) throws {
        for (name, decision) in merged.decisions {
            guard case let .conflict(local, remote, ancestor) = decision else { continue }
            let row = MergeConflictRow(
                id: SQLValue.uuid(UUID()),
                objectType: objectType,
                objectId: SQLValue.uuid(objectID),
                fieldName: name,
                localValue: local,
                remoteValue: remote,
                ancestorValue: ancestor,
                detectedAt: RFC3339.utcString(from: Date()),
                resolution: "retained_local",
                resolvedAt: nil
            )
            try row.insert(db)
        }
    }
}
