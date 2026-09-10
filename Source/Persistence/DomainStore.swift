#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import Foundation

public struct DomainStore: Sendable {
    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func missions() throws -> [MissionRecord] {
        try db.read { db in
            try db.query("SELECT * FROM missions WHERE deleted_at IS NULL ORDER BY updated_at DESC")
                .compactMap(Self.mission(from:))
        }
    }

    public func tasks() throws -> [TaskRecord] {
        try db.read { db in
            try db.query("SELECT * FROM tasks WHERE deleted_at IS NULL ORDER BY due_date IS NULL, due_date ASC")
                .compactMap(Self.task(from:))
        }
    }

    public func habits() throws -> [HabitRecord] {
        try db.read { db in
            try db.query("SELECT * FROM habits WHERE deleted_at IS NULL ORDER BY title ASC")
                .compactMap(Self.habit(from:))
        }
    }

    public func checkIns(habitID: UUID) throws -> [CheckInRecord] {
        try db.read { db in
            try db.query(
                "SELECT * FROM checkins WHERE habit_id = ? AND deleted_at IS NULL ORDER BY occurred_on DESC",
                [habitID.uuidString.lowercased()]
            ).compactMap(Self.checkIn(from:))
        }
    }

    public func upsertMission(_ record: MissionRecord) throws {
        try db.write { db in
            try db.execute(
                """
                INSERT INTO missions(id, title, notes, status, created_at, updated_at, revision, modified_by_device, deleted_at)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    notes = excluded.notes,
                    status = excluded.status,
                    updated_at = excluded.updated_at,
                    revision = excluded.revision,
                    modified_by_device = excluded.modified_by_device,
                    deleted_at = excluded.deleted_at
                """,
                [
                    record.id.uuidString.lowercased(),
                    record.title,
                    record.notes,
                    record.status.rawValue,
                    RFC3339.utcString(from: record.createdAt),
                    RFC3339.utcString(from: record.updatedAt),
                    record.revision,
                    record.modifiedByDevice.uuidString.lowercased(),
                    record.deletedAt.map(RFC3339.utcString(from:))
                ]
            )
            try enqueue(db, recordType: "CDMission", recordName: record.id, revision: record.revision, payload: record)
        }
    }

    public func upsertTask(_ record: TaskRecord) throws {
        try db.write { db in
            try db.execute(
                """
                INSERT INTO tasks(id, title, notes, due_date, is_completed, completed_at, mission_id, workload, created_at, updated_at, revision, modified_by_device, deleted_at)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    notes = excluded.notes,
                    due_date = excluded.due_date,
                    is_completed = excluded.is_completed,
                    completed_at = excluded.completed_at,
                    mission_id = excluded.mission_id,
                    workload = excluded.workload,
                    updated_at = excluded.updated_at,
                    revision = excluded.revision,
                    modified_by_device = excluded.modified_by_device,
                    deleted_at = excluded.deleted_at
                """,
                [
                    record.id.uuidString.lowercased(),
                    record.title,
                    record.notes,
                    record.dueDate.map(RFC3339.utcString(from:)),
                    record.isCompleted ? 1 : 0,
                    record.completedAt.map(RFC3339.utcString(from:)),
                    record.missionID?.uuidString.lowercased(),
                    record.workload,
                    RFC3339.utcString(from: record.createdAt),
                    RFC3339.utcString(from: record.updatedAt),
                    record.revision,
                    record.modifiedByDevice.uuidString.lowercased(),
                    record.deletedAt.map(RFC3339.utcString(from:))
                ]
            )
            try enqueue(db, recordType: "CDTaskOccurrence", recordName: record.id, revision: record.revision, payload: record)
        }
    }

    public func upsertHabit(_ record: HabitRecord) throws {
        try db.write { db in
            try db.execute(
                """
                INSERT INTO habits(id, title, notes, created_at, updated_at, revision, modified_by_device, deleted_at)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    notes = excluded.notes,
                    updated_at = excluded.updated_at,
                    revision = excluded.revision,
                    modified_by_device = excluded.modified_by_device,
                    deleted_at = excluded.deleted_at
                """,
                [
                    record.id.uuidString.lowercased(),
                    record.title,
                    record.notes,
                    RFC3339.utcString(from: record.createdAt),
                    RFC3339.utcString(from: record.updatedAt),
                    record.revision,
                    record.modifiedByDevice.uuidString.lowercased(),
                    record.deletedAt.map(RFC3339.utcString(from:))
                ]
            )
            try enqueue(db, recordType: "CDHabit", recordName: record.id, revision: record.revision, payload: record)
        }
    }

    public func upsertCheckIn(_ record: CheckInRecord) throws {
        try db.write { db in
            try db.execute(
                """
                INSERT INTO checkins(id, habit_id, occurred_on, note, created_at, revision, modified_by_device, deleted_at)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    occurred_on = excluded.occurred_on,
                    note = excluded.note,
                    revision = excluded.revision,
                    deleted_at = excluded.deleted_at
                """,
                [
                    record.id.uuidString.lowercased(),
                    record.habitID.uuidString.lowercased(),
                    RFC3339.utcString(from: record.occurredOn),
                    record.note,
                    RFC3339.utcString(from: record.createdAt),
                    record.revision,
                    record.modifiedByDevice.uuidString.lowercased(),
                    record.deletedAt.map(RFC3339.utcString(from:))
                ]
            )
            try enqueue(db, recordType: "CDCheckIn", recordName: record.id, revision: record.revision, payload: record)
        }
    }

    private func enqueue<T: Encodable>(
        _ db: SQLiteDatabase,
        recordType: String,
        recordName: UUID,
        revision: Int64,
        payload: T
    ) throws {
        let json = String(decoding: try JSONCoding.encoder(pretty: false).encode(payload), as: UTF8.self)
        try db.execute(
            """
            INSERT INTO cloud_outbox(id, record_type, record_name, operation, revision, payload_json, modified_by_device, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                UUID().uuidString.lowercased(),
                recordType,
                recordName.uuidString.lowercased(),
                "upsert",
                revision,
                json,
                self.db.deviceID.uuidString.lowercased(),
                RFC3339.utcString(from: Date())
            ]
        )
    }

    private static func mission(from row: [String: String]) -> MissionRecord? {
        guard let id = row["id"].flatMap(UUID.init(uuidString:)),
              let title = row["title"],
              let createdAt = RFC3339.parse(row["created_at"]),
              let updatedAt = RFC3339.parse(row["updated_at"]),
              let device = row["modified_by_device"].flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return MissionRecord(
            id: id,
            title: title,
            notes: row["notes"] ?? "",
            status: MissionStatus(rawValue: row["status"] ?? "") ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: Int64(row["revision"] ?? "1") ?? 1,
            modifiedByDevice: device,
            deletedAt: RFC3339.parse(row["deleted_at"])
        )
    }

    private static func task(from row: [String: String]) -> TaskRecord? {
        guard let id = row["id"].flatMap(UUID.init(uuidString:)),
              let title = row["title"],
              let createdAt = RFC3339.parse(row["created_at"]),
              let updatedAt = RFC3339.parse(row["updated_at"]),
              let device = row["modified_by_device"].flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return TaskRecord(
            id: id,
            title: title,
            notes: row["notes"] ?? "",
            dueDate: RFC3339.parse(row["due_date"]),
            isCompleted: row["is_completed"] == "1",
            completedAt: RFC3339.parse(row["completed_at"]),
            missionID: row["mission_id"].flatMap(UUID.init(uuidString:)),
            workload: Int(row["workload"] ?? "1") ?? 1,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: Int64(row["revision"] ?? "1") ?? 1,
            modifiedByDevice: device,
            deletedAt: RFC3339.parse(row["deleted_at"])
        )
    }

    private static func habit(from row: [String: String]) -> HabitRecord? {
        guard let id = row["id"].flatMap(UUID.init(uuidString:)),
              let title = row["title"],
              let createdAt = RFC3339.parse(row["created_at"]),
              let updatedAt = RFC3339.parse(row["updated_at"]),
              let device = row["modified_by_device"].flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return HabitRecord(
            id: id,
            title: title,
            notes: row["notes"] ?? "",
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: Int64(row["revision"] ?? "1") ?? 1,
            modifiedByDevice: device,
            deletedAt: RFC3339.parse(row["deleted_at"])
        )
    }

    private static func checkIn(from row: [String: String]) -> CheckInRecord? {
        guard let id = row["id"].flatMap(UUID.init(uuidString:)),
              let habitID = row["habit_id"].flatMap(UUID.init(uuidString:)),
              let occurredOn = RFC3339.parse(row["occurred_on"]),
              let createdAt = RFC3339.parse(row["created_at"]),
              let device = row["modified_by_device"].flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return CheckInRecord(
            id: id,
            habitID: habitID,
            occurredOn: occurredOn,
            note: row["note"] ?? "",
            createdAt: createdAt,
            revision: Int64(row["revision"] ?? "1") ?? 1,
            modifiedByDevice: device,
            deletedAt: RFC3339.parse(row["deleted_at"])
        )
    }
}
