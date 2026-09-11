import CalendarCountdownCore
import CryptoKit
import Foundation
import GRDB

enum CloudRecordIdentity {
    static let countdownPreferences = uuid(from: "CDCountdownPreferences")

    static func habitPeriod(habitID: UUID, periodKey: String) -> UUID {
        uuid(from: "CDHabitPeriod:\(habitID.uuidString.lowercased()):\(periodKey)")
    }

    static func uuid(from seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum DomainWriter {
    static func requireRevision(_ actual: Int64, options: WriteOptions) throws {
        if let expected = options.ifRevision, expected != actual {
            throw DomainError.revisionConflict(expected: expected, actual: actual)
        }
    }

    static func enqueueOutbox(
        _ db: Database,
        recordType: String,
        recordName: UUID,
        operation: String,
        revision: Int64,
        now: Date,
        payloadJSON: String? = nil,
        fields: [String: CloudFieldSnapshot] = [:],
        modifiedByDevice: UUID? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws {
        try db.execute(
            sql: "DELETE FROM cloud_outbox WHERE record_type = ? AND record_name = ?",
            arguments: [recordType, SQLValue.uuid(recordName)]
        )
        let fieldsJSON = fields.isEmpty ? nil : try SQLValue.json(fields)
        let row = CloudOutboxRow(
            id: SQLValue.uuid(UUID()),
            recordType: recordType,
            recordName: SQLValue.uuid(recordName),
            operation: operation,
            localRevision: revision,
            enqueuedAt: RFC3339.utcString(from: now),
            retryCount: 0,
            lastErrorCode: nil,
            payloadJson: payloadJSON,
            fieldsJson: fieldsJSON,
            modifiedByDevice: modifiedByDevice.map(SQLValue.uuid),
            updatedAt: SQLValue.date(updatedAt ?? now),
            deletedAt: SQLValue.date(deletedAt)
        )
        try row.insert(db)
        if let objectType = objectType(forRecordType: recordType), !fields.isEmpty {
            try seedAncestorsIfNeeded(
                db,
                objectType: objectType,
                objectID: recordName,
                fields: fields
            )
        }
    }

    static func objectType(forRecordType recordType: String) -> String? {
        switch recordType {
        case "CDMission": "mission"
        case "CDTaskSeries": "task_series"
        case "CDTaskOccurrence": "task_occurrence"
        case "CDHabit": "habit"
        case "CDManagedEvent": "managed_event"
        case "CDCountdownSelection": "countdown_selection"
        case "CDCountdownPreferences": "countdown_preferences"
        default: nil
        }
    }

    static func seedAncestorsIfNeeded(
        _ db: Database,
        objectType: String,
        objectID: UUID,
        fields: [String: CloudFieldSnapshot]
    ) throws {
        let existing = try ancestorSnapshots(db, objectType: objectType, objectID: objectID)
        let missing = fields.filter { existing[$0.key] == nil }
        guard !missing.isEmpty else { return }
        try persistAncestors(db, objectType: objectType, objectID: objectID, fields: missing)
    }

    static func enqueueEncoded<T: Encodable>(
        _ db: Database,
        recordType: String,
        recordName: UUID,
        operation: String,
        revision: Int64,
        payload: T,
        fields: [String: CloudFieldSnapshot] = [:],
        modifiedByDevice: UUID,
        updatedAt: Date,
        deletedAt: Date? = nil,
        now: Date
    ) throws {
        try enqueueOutbox(
            db,
            recordType: recordType,
            recordName: recordName,
            operation: operation,
            revision: revision,
            now: now,
            payloadJSON: try SQLValue.json(payload),
            fields: fields,
            modifiedByDevice: modifiedByDevice,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    static func ackOutbox(_ db: Database, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        try db.execute(
            sql: "DELETE FROM cloud_outbox WHERE id IN (\(placeholders))",
            arguments: StatementArguments(ids)
        )
    }

    static func journal(
        _ db: Database,
        options: WriteOptions,
        command: String,
        objectType: String,
        objectID: UUID,
        before: Int64?,
        after: Int64?,
        summary: String
    ) throws {
        let row = OperationJournalRow(
            requestId: SQLValue.uuid(options.requestID),
            actor: options.actor.rawValue,
            command: command,
            objectType: objectType,
            objectId: SQLValue.uuid(objectID),
            beforeRevision: before,
            afterRevision: after,
            effectSummary: summary,
            createdAt: RFC3339.utcString(from: options.now)
        )
        try row.insert(db)
    }

    static func pendingProjection(
        _ db: Database,
        options: WriteOptions,
        command: String,
        objectType: String,
        objectID: UUID
    ) throws {
        let row = PendingOperationRow(
            id: SQLValue.uuid(UUID()),
            requestId: SQLValue.uuid(options.requestID),
            command: command,
            objectType: objectType,
            objectId: SQLValue.uuid(objectID),
            stage: "projection",
            startedAt: RFC3339.utcString(from: options.now),
            updatedAt: RFC3339.utcString(from: options.now),
            retryCount: 0,
            lastErrorCode: nil
        )
        try? row.insert(db)
    }

    static func pendingOperations(_ db: Database, stage: String = "projection") throws -> [PendingOperationRow] {
        try PendingOperationRow.filter(Column("stage") == stage).fetchAll(db)
    }

    static func completePending(_ db: Database, requestID: UUID, now: Date) throws {
        try db.execute(
            sql: """
                UPDATE pending_operations
                SET stage = 'completed', updated_at = ?
                WHERE request_id = ?
                """,
            arguments: [RFC3339.utcString(from: now), SQLValue.uuid(requestID)]
        )
    }

    static func failPending(_ db: Database, requestID: UUID, code: String, now: Date) throws {
        try db.execute(
            sql: """
                UPDATE pending_operations
                SET retry_count = retry_count + 1, last_error_code = ?, updated_at = ?
                WHERE request_id = ?
                """,
            arguments: [code, RFC3339.utcString(from: now), SQLValue.uuid(requestID)]
        )
    }

    static func ancestorSnapshots(
        _ db: Database,
        objectType: String,
        objectID: UUID
    ) throws -> [String: FieldSnapshot] {
        let rows = try FieldAncestorRow
            .filter(
                sql: "object_type = ? AND object_id = ?",
                arguments: [objectType, SQLValue.uuid(objectID)]
            )
            .fetchAll(db)
        var result: [String: FieldSnapshot] = [:]
        for row in rows {
            guard let hlc = HybridLogicalTimestamp.parse(row.hlc) else { continue }
            result[row.fieldName] = FieldSnapshot(value: row.value, hlc: hlc)
        }
        return result
    }

    static func persistAncestors(
        _ db: Database,
        objectType: String,
        objectID: UUID,
        fields: [String: CloudFieldSnapshot]
    ) throws {
        for (name, payload) in fields {
            try db.execute(
                sql: """
                    INSERT INTO field_ancestors(object_type, object_id, field_name, value, hlc)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(object_type, object_id, field_name)
                    DO UPDATE SET value = excluded.value, hlc = excluded.hlc
                    """,
                arguments: [
                    objectType,
                    SQLValue.uuid(objectID),
                    name,
                    payload.value,
                    payload.hlc
                ]
            )
        }
    }

    static func rememberIdempotency(
        _ db: Database,
        options: WriteOptions,
        command: String,
        payloadHash: String,
        objectID: UUID,
        revision: Int64
    ) throws {
        guard let key = options.idempotencyKey else { return }
        let body = IdempotentAck(objectID: objectID, revision: revision)
        let row = IdempotencyRow(
            key: key,
            commandName: command,
            requestHash: payloadHash,
            responseJson: try SQLValue.json(body),
            createdAt: RFC3339.utcString(from: options.now),
            expiresAt: RFC3339.utcString(from: options.now.addingTimeInterval(86_400 * 7))
        )
        try row.insert(db)
    }

    static func existingIdempotency(
        _ db: Database,
        options: WriteOptions,
        command: String,
        payloadHash: String
    ) throws -> IdempotentAck? {
        guard let key = options.idempotencyKey else { return nil }
        guard let row = try IdempotencyRow
            .filter(Column("key") == key)
            .fetchOne(db) else { return nil }
        if row.commandName != command || row.requestHash != payloadHash {
            throw DomainError(
                code: .idempotencyConflict,
                message: "幂等键已被不同请求使用。",
                details: ["key": key]
            )
        }
        return try JSONCoding.decoder().decode(IdempotentAck.self, from: Data(row.responseJson.utf8))
    }

    static func payloadHash<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONCoding.encoder(pretty: false).encode(value)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func touchField(
        _ db: Database,
        objectType: String,
        objectID: UUID,
        field: String,
        deviceID: UUID,
        now: Date
    ) throws {
        let hlc = HybridLogicalTimestamp.now(deviceID: deviceID, at: now)
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
                field,
                hlc.wireValue,
                SQLValue.uuid(deviceID)
            ]
        )
    }

    static func touchFields(
        _ db: Database,
        objectType: String,
        objectID: UUID,
        fields: [String],
        deviceID: UUID,
        now: Date
    ) throws {
        for field in fields {
            try touchField(db, objectType: objectType, objectID: objectID, field: field, deviceID: deviceID, now: now)
        }
    }

    static func fieldSnapshots(
        _ db: Database,
        objectType: String,
        objectID: UUID,
        values: [String: String?],
        deviceID: UUID,
        now: Date
    ) throws -> [String: CloudFieldSnapshot] {
        var result: [String: CloudFieldSnapshot] = [:]
        for (name, value) in values {
            if let row = try FieldVersionRow
                .filter(
                    sql: "object_type = ? AND object_id = ? AND field_name = ?",
                    arguments: [objectType, SQLValue.uuid(objectID), name]
                )
                .fetchOne(db)
            {
                result[name] = CloudFieldSnapshot(value: value, hlc: row.hlc)
            } else {
                result[name] = CloudFieldSnapshot(
                    value: value,
                    hlc: HybridLogicalTimestamp.now(deviceID: deviceID, at: now)
                )
            }
        }
        return result
    }
}

struct IdempotentAck: Codable, Sendable {
    var objectID: UUID
    var revision: Int64
}

public struct CanonicalSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var timeZoneIdentifier: String
    public var appVersion: String
    public var missions: [MissionDefinition]
    public var taskSeries: [TaskSeries]
    public var occurrences: [TaskOccurrence]
    public var habits: [HabitDefinition]
    public var habitPeriods: [HabitPeriod]
    public var checkIns: [CheckInRecord]
    public var projectionSettings: ProjectionSettings?

    public init(
        schemaVersion: Int = 2,
        exportedAt: Date = Date(),
        timeZoneIdentifier: String,
        appVersion: String = ProductConstants.version,
        missions: [MissionDefinition] = [],
        taskSeries: [TaskSeries] = [],
        occurrences: [TaskOccurrence] = [],
        habits: [HabitDefinition] = [],
        habitPeriods: [HabitPeriod] = [],
        checkIns: [CheckInRecord] = [],
        projectionSettings: ProjectionSettings? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.appVersion = appVersion
        self.missions = missions
        self.taskSeries = taskSeries
        self.occurrences = occurrences
        self.habits = habits
        self.habitPeriods = habitPeriods
        self.checkIns = checkIns
        self.projectionSettings = projectionSettings
    }
}

public struct ImportPreview: Codable, Equatable, Sendable {
    public var dryRun: Bool
    public var missionCreates: Int
    public var missionUpdates: Int
    public var taskCreates: Int
    public var habitCreates: Int
    public var checkInCreates: Int
    public var conflicts: [String]
}

enum DomainQueries {
    static func mission(_ db: Database, id: UUID) throws -> MissionDefinition? {
        try MissionRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
    }

    static func missions(_ db: Database) throws -> [MissionDefinition] {
        try MissionRow
            .filter(sql: "deleted_at IS NULL")
            .order(sql: "sort_key ASC, title ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func series(_ db: Database, id: UUID) throws -> TaskSeries? {
        try TaskSeriesRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
    }

    static func seriesList(_ db: Database, missionID: UUID? = nil) throws -> [TaskSeries] {
        var sql = "deleted_at IS NULL"
        var arguments: StatementArguments = []
        if let missionID {
            sql += " AND mission_id = ?"
            arguments += [SQLValue.uuid(missionID)]
        }
        return try TaskSeriesRow
            .filter(sql: sql, arguments: arguments)
            .order(sql: "sort_key ASC, title ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func seriesIncludingDeleted(_ db: Database, id: UUID) throws -> TaskSeries? {
        try series(db, id: id)
    }

    static func occurrence(_ db: Database, id: UUID) throws -> TaskOccurrence? {
        try TaskOccurrenceRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
    }

    static func occurrenceIncludingDeleted(_ db: Database, id: UUID) throws -> TaskOccurrence? {
        try occurrence(db, id: id)
    }

    static func occurrence(_ db: Database, key: String) throws -> TaskOccurrence? {
        try TaskOccurrenceRow
            .filter(Column("occurrence_key") == key)
            .fetchOne(db)?
            .domain()
    }

    static func occurrences(forSeries db: Database, seriesID: UUID) throws -> [TaskOccurrence] {
        try TaskOccurrenceRow
            .filter(sql: "series_id = ? AND deleted_at IS NULL", arguments: [SQLValue.uuid(seriesID)])
            .order(sql: "planned_due ASC, occurrence_key ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func openOccurrences(_ db: Database) throws -> [TaskOccurrence] {
        try TaskOccurrenceRow
            .filter(sql: "deleted_at IS NULL AND status = 'open'")
            .order(sql: "planned_due IS NULL, planned_due ASC, occurrence_key ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func habit(_ db: Database, id: UUID) throws -> HabitDefinition? {
        try HabitRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
    }

    static func habits(_ db: Database) throws -> [HabitDefinition] {
        try HabitRow
            .filter(sql: "deleted_at IS NULL")
            .order(sql: "title ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func checkIn(_ db: Database, id: UUID) throws -> CheckInRecord? {
        try CheckInRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
    }

    static func checkIns(_ db: Database, habitID: UUID) throws -> [CheckInRecord] {
        try CheckInRow
            .filter(sql: "habit_id = ?", arguments: [SQLValue.uuid(habitID)])
            .order(sql: "effective_at ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func periods(_ db: Database, habitID: UUID) throws -> [HabitPeriod] {
        try HabitPeriodRow
            .filter(sql: "habit_id = ?", arguments: [SQLValue.uuid(habitID)])
            .order(sql: "period_key ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func projectionSettings(_ db: Database) throws -> ProjectionSettings? {
        try ProjectionSettingsRow.fetchOne(db)?.domain()
    }

    static func managedEvent(_ db: Database, id: UUID) throws -> ManagedEventRecord? {
        try ManagedEventRow
            .filter(sql: "id = ? AND deleted_at IS NULL", arguments: [SQLValue.uuid(id)])
            .fetchOne(db)?
            .domain()
    }

    static func managedEventIncludingDeleted(_ db: Database, id: UUID) throws -> ManagedEventRecord? {
        try ManagedEventRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
    }

    static func countdownSelection(
        _ db: Database,
        id: UUID,
        includingDeleted: Bool = false
    ) throws -> CountdownSelection? {
        if includingDeleted {
            return try CountdownSelectionRow.fetchOne(db, key: SQLValue.uuid(id))?.domain()
        }
        return try CountdownSelectionRow
            .filter(sql: "id = ? AND deleted_at IS NULL", arguments: [SQLValue.uuid(id)])
            .fetchOne(db)?
            .domain()
    }

    static func countdownSelections(_ db: Database) throws -> [CountdownSelection] {
        try CountdownSelectionRow
            .filter(sql: "deleted_at IS NULL")
            .order(sql: "selected_at ASC")
            .fetchAll(db)
            .map { try $0.domain() }
    }

    static func countdownPreferences(_ db: Database) throws -> CountdownDisplayPreferences {
        let pinned = try CountdownPreferencesRow
            .fetchOne(db, key: SQLValue.uuid(CloudRecordIdentity.countdownPreferences))
            .flatMap { row in row.pinnedSelectionId.flatMap { UUID(uuidString: $0) } }
        let hidden = try CountdownHiddenCalendarRow.fetchAll(db).map(\.calendarIdentifier)
        return CountdownDisplayPreferences(
            untrackedCalendarIdentifiers: Set(hidden),
            pinnedSelectionID: pinned
        )
    }

    static func snapshot(_ db: Database, timeZoneIdentifier: String) throws -> CanonicalSnapshot {
        CanonicalSnapshot(
            exportedAt: Date(),
            timeZoneIdentifier: timeZoneIdentifier,
            missions: try MissionRow.fetchAll(db).map { try $0.domain() },
            taskSeries: try TaskSeriesRow.fetchAll(db).map { try $0.domain() },
            occurrences: try TaskOccurrenceRow.fetchAll(db).map { try $0.domain() },
            habits: try HabitRow.fetchAll(db).map { try $0.domain() },
            habitPeriods: try HabitPeriodRow.fetchAll(db).map { try $0.domain() },
            checkIns: try CheckInRow.fetchAll(db).map { try $0.domain() },
            projectionSettings: try ProjectionSettingsRow.fetchOne(db)?.domain()
        )
    }
}
