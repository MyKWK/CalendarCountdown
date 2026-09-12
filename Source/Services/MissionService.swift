import CalendarCountdownCore
import Foundation
import GRDB

public struct MissionService: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func create(_ command: CreateMissionCommand, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        let mission = try MissionDefinition(
            title: command.title,
            markdownDescription: command.markdownDescription,
            color: command.color,
            icon: command.icon,
            status: command.status,
            targetDate: command.targetDate,
            defaultWorkload: command.defaultWorkload,
            createdAt: options.now,
            updatedAt: options.now,
            modifiedByDevice: db.deviceID
        ).validated()
        if options.dryRun {
            return MissionWriteResult(
                mission: mission,
                progress: ProgressCalculator.breakdown(from: []),
                effects: WriteEffects(sqliteCommitted: false, dryRun: true)
            )
        }
        return try db.write { db in
            let hash = try DomainWriter.payloadHash(command)
            if let ack = try DomainWriter.existingIdempotency(db, options: options, command: "missions.create", payloadHash: hash),
               let existing = try DomainQueries.mission(db, id: ack.objectID) {
                return try Self.result(existing, db: db, committed: true)
            }
            try MissionRow(mission).insert(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDMission",
                recordName: mission.id,
                operation: "upsert",
                revision: mission.revision,
                payload: mission,
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "mission",
                    objectID: mission.id,
                    values: [
                        "title": mission.title,
                        "description_md": mission.markdownDescription,
                        "color": mission.color,
                        "icon": mission.icon,
                        "status": mission.status.rawValue
                    ],
                    deviceID: mission.modifiedByDevice,
                    now: mission.updatedAt
                ),
                modifiedByDevice: mission.modifiedByDevice,
                updatedAt: mission.updatedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "missions.create",
                objectType: "mission",
                objectID: mission.id,
                before: nil,
                after: mission.revision,
                summary: "新建使命：\(mission.title)"
            )
            try DomainWriter.rememberIdempotency(
                db,
                options: options,
                command: "missions.create",
                payloadHash: hash,
                objectID: mission.id,
                revision: mission.revision
            )
            try DomainWriter.touchFields(
                db,
                objectType: "mission",
                objectID: mission.id,
                fields: ["title", "description_md", "color", "icon", "status"],
                deviceID: mission.modifiedByDevice,
                now: mission.updatedAt
            )
            return try Self.result(mission, db: db, committed: true)
        }
    }

    public func list() throws -> [MissionWriteResult] {
        try db.read { db in
            let missions = try DomainQueries.missions(db)
            let activities = try Dictionary(
                uniqueKeysWithValues: missions.compactMap { mission -> (UUID, Date)? in
                    guard let occurredAt = try DomainWriter.missionActivity(db, missionID: mission.id).first?.occurredAt else {
                        return nil
                    }
                    return (mission.id, occurredAt)
                }
            )
            return try missions
                .map { try Self.result($0, db: db, committed: true) }
                .sorted { left, right in
                    let leftActivity = activities[left.mission.id] ?? left.mission.updatedAt
                    let rightActivity = activities[right.mission.id] ?? right.mission.updatedAt
                    if leftActivity != rightActivity { return leftActivity > rightActivity }
                    return left.mission.sortKey > right.mission.sortKey
                }
        }
    }

    public func get(id: UUID) throws -> MissionWriteResult {
        try db.read { db in
            guard let mission = try DomainQueries.mission(db, id: id), mission.deletedAt == nil else {
                throw DomainError.notFound(.missionNotFound, id: id)
            }
            return try Self.result(mission, db: db, committed: true)
        }
    }

    public func progress(id: UUID, previous: (done: Int, total: Int)? = nil) throws -> MissionProgressBreakdown {
        try get(id: id).progress
    }

    public func activity(id: UUID) throws -> [MissionActivityEntry] {
        try db.read { db in
            guard let mission = try DomainQueries.mission(db, id: id), mission.deletedAt == nil else {
                throw DomainError.notFound(.missionNotFound, id: id)
            }
            return try DomainWriter.missionActivity(db, missionID: mission.id)
        }
    }

    public func update(
        id: UUID,
        title: String? = nil,
        markdownDescription: String? = nil,
        options: WriteOptions = WriteOptions()
    ) throws -> MissionWriteResult {
        try patch(
            id: id,
            command: PatchMissionCommand(title: title, markdownDescription: markdownDescription),
            options: options
        )
    }

    public func patch(
        id: UUID,
        command: PatchMissionCommand,
        options: WriteOptions = WriteOptions()
    ) throws -> MissionWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var mission = try DomainQueries.mission(db, id: id), mission.deletedAt == nil else {
                throw DomainError.notFound(.missionNotFound, id: id)
            }
            try DomainWriter.requireRevision(mission.revision, options: options)
            if options.dryRun {
                return try Self.result(mission, db: db, committed: false, dryRun: true)
            }
            let before = mission.revision
            var touched: [String] = []
            if let title = command.title {
                mission.title = title
                touched.append("title")
            }
            if let markdownDescription = command.markdownDescription {
                mission.markdownDescription = markdownDescription
                touched.append("description_md")
            }
            if let color = command.color {
                mission.color = color
                touched.append("color")
            }
            if let icon = command.icon {
                mission.icon = icon
                touched.append("icon")
            }
            if let status = command.status {
                mission.status = status
                touched.append("status")
            }
            if command.clearTargetDate == true {
                mission.targetDate = nil
            } else if let targetDate = command.targetDate {
                mission.targetDate = targetDate
            }
            if let workload = command.defaultWorkload { mission.defaultWorkload = workload }
            mission.updatedAt = options.now
            mission.revision += 1
            mission.modifiedByDevice = deviceID
            mission = try mission.validated()
            try MissionRow(mission).update(db)
            try DomainWriter.touchFields(
                db,
                objectType: "mission",
                objectID: mission.id,
                fields: touched,
                deviceID: deviceID,
                now: options.now
            )
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDMission",
                recordName: mission.id,
                operation: "upsert",
                revision: mission.revision,
                payload: mission,
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "mission",
                    objectID: mission.id,
                    values: [
                        "title": mission.title,
                        "description_md": mission.markdownDescription,
                        "color": mission.color,
                        "icon": mission.icon,
                        "status": mission.status.rawValue
                    ],
                    deviceID: deviceID,
                    now: options.now
                ),
                modifiedByDevice: deviceID,
                updatedAt: mission.updatedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "missions.update",
                objectType: "mission",
                objectID: mission.id,
                before: before,
                after: mission.revision,
                summary: "编辑使命：\(mission.title)（\(touched.joined(separator: "、"))）"
            )
            return try Self.result(mission, db: db, committed: true)
        }
    }

    public func addTask(missionID: UUID, seriesID: UUID, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        try attach(missionID: missionID, seriesID: seriesID, remove: false, options: options)
    }

    public func removeTask(missionID: UUID, seriesID: UUID, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        try attach(missionID: missionID, seriesID: seriesID, remove: true, options: options)
    }

    public func complete(id: UUID, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var mission = try DomainQueries.mission(db, id: id), mission.deletedAt == nil else {
                throw DomainError.notFound(.missionNotFound, id: id)
            }
            try DomainWriter.requireRevision(mission.revision, options: options)
            let progress = try Self.result(mission, db: db, committed: false).progress
            if progress.progress != 1, options.actor != .appleCompletion {
                throw DomainError.validation("使命进度尚未达到 100%，不能标记完成。")
            }
            if options.dryRun {
                return MissionWriteResult(mission: mission, progress: progress, effects: WriteEffects(sqliteCommitted: false, dryRun: true))
            }
            let before = mission.revision
            mission.status = .completed
            mission.updatedAt = options.now
            mission.revision += 1
            mission.modifiedByDevice = deviceID
            try MissionRow(mission).update(db)
            try DomainWriter.touchFields(
                db,
                objectType: "mission",
                objectID: mission.id,
                fields: ["status"],
                deviceID: deviceID,
                now: options.now
            )
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDMission",
                recordName: mission.id,
                operation: "upsert",
                revision: mission.revision,
                payload: mission,
                modifiedByDevice: deviceID,
                updatedAt: mission.updatedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "missions.complete",
                objectType: "mission",
                objectID: mission.id,
                before: before,
                after: mission.revision,
                summary: "完成使命：\(mission.title)"
            )
            return try Self.result(mission, db: db, committed: true)
        }
    }

    public func archive(id: UUID, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        try setStatus(id: id, status: .archived, options: options)
    }

    public func pause(id: UUID, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        try setStatus(id: id, status: .paused, options: options)
    }

    public func delete(id: UUID, permanent: Bool, confirmID: UUID?, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        if permanent {
            guard confirmID == id else {
                throw DomainError.validation("永久删除必须提供 --confirm-id。")
            }
        }
        let deviceID = db.deviceID
        return try db.write { db in
            guard var mission = try DomainQueries.mission(db, id: id) else {
                throw DomainError.notFound(.missionNotFound, id: id)
            }
            if options.dryRun {
                return try Self.result(mission, db: db, committed: false, dryRun: true)
            }
            let before = mission.revision
            mission.status = .archived
            mission.deletedAt = options.now
            mission.updatedAt = options.now
            mission.revision += 1
            mission.modifiedByDevice = deviceID
            try MissionRow(mission).update(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDMission",
                recordName: mission.id,
                operation: "delete",
                revision: mission.revision,
                payload: mission,
                modifiedByDevice: deviceID,
                updatedAt: mission.updatedAt,
                deletedAt: mission.deletedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "missions.delete",
                objectType: "mission",
                objectID: mission.id,
                before: before,
                after: mission.revision,
                summary: "删除使命：\(mission.title)"
            )
            return try Self.result(mission, db: db, committed: true)
        }
    }

    public func setStatus(id: UUID, status: MissionStatus, options: WriteOptions = WriteOptions()) throws -> MissionWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var mission = try DomainQueries.mission(db, id: id), mission.deletedAt == nil else {
                throw DomainError.notFound(.missionNotFound, id: id)
            }
            try DomainWriter.requireRevision(mission.revision, options: options)
            if options.dryRun {
                mission.status = status
                return try Self.result(mission, db: db, committed: false, dryRun: true)
            }
            let before = mission.revision
            mission.status = status
            mission.updatedAt = options.now
            mission.revision += 1
            mission.modifiedByDevice = deviceID
            try MissionRow(mission).update(db)
            try DomainWriter.enqueueOutbox(
                db,
                recordType: "CDMission",
                recordName: mission.id,
                operation: "upsert",
                revision: mission.revision,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "missions.update",
                objectType: "mission",
                objectID: mission.id,
                before: before,
                after: mission.revision,
                summary: "更新使命状态：\(mission.title)（\(status.rawValue)）"
            )
            return try Self.result(mission, db: db, committed: true)
        }
    }

    private func attach(missionID: UUID, seriesID: UUID, remove: Bool, options: WriteOptions) throws -> MissionWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard let mission = try DomainQueries.mission(db, id: missionID), mission.deletedAt == nil else {
                throw DomainError.notFound(.missionNotFound, id: missionID)
            }
            guard var series = try DomainQueries.series(db, id: seriesID), series.deletedAt == nil else {
                throw DomainError.notFound(.taskNotFound, id: seriesID)
            }
            try DomainWriter.requireRevision(series.revision, options: options)
            if options.dryRun {
                return try Self.result(mission, db: db, committed: false, dryRun: true)
            }
            let before = series.revision
            series.missionID = remove ? nil : missionID
            series.updatedAt = options.now
            series.revision += 1
            series.modifiedByDevice = deviceID
            try TaskSeriesRow(series).update(db)
            try DomainWriter.enqueueOutbox(
                db,
                recordType: "CDTaskSeries",
                recordName: series.id,
                operation: "upsert",
                revision: series.revision,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: remove ? "missions.remove-task" : "missions.add-task",
                objectType: "task_series",
                objectID: series.id,
                before: before,
                after: series.revision,
                summary: remove ? "从使命移出任务：\(series.title)" : "加入任务：\(series.title)"
            )
            return try Self.result(mission, db: db, committed: true)
        }
    }

    private static func result(
        _ mission: MissionDefinition,
        db: Database,
        committed: Bool,
        dryRun: Bool = false
    ) throws -> MissionWriteResult {
        let seriesList = try DomainQueries.seriesList(db, missionID: mission.id)
        var contributions: [OccurrenceContribution] = []
        var expected = 0
        var completed = 0
        let calendar = Calendar(identifier: .gregorian)
        let windowStart = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        for series in seriesList {
            let occurrences = try DomainQueries.occurrences(forSeries: db, seriesID: series.id)
            for occurrence in occurrences {
                contributions.append(ProgressCalculator.contribution(series: series, occurrence: occurrence))
                if series.isInfinite {
                    if let due = occurrence.plannedDue, due >= windowStart {
                        expected += 1
                        if occurrence.status == .completed { completed += 1 }
                    }
                }
            }
        }
        let habits = try DomainQueries.habits(db).filter { $0.missionID == mission.id }
        for habit in habits {
            let timeZone = TimeZone.current
            let keys = HabitStatisticsEngine.expectedPeriodKeys(
                from: LocalDate.from(windowStart, timeZone: timeZone),
                to: LocalDate.from(Date(), timeZone: timeZone),
                schedule: habit.schedule,
                timeZone: timeZone
            )
            expected += keys.count
            let checkIns = try DomainQueries.checkIns(db, habitID: habit.id)
            let periods = try DomainQueries.periods(db, habitID: habit.id)
            for key in keys {
                let evaluation = HabitStatisticsEngine.evaluate(
                    habit: habit,
                    periodKey: key,
                    checkIns: checkIns,
                    period: periods.first(where: { $0.periodKey == key }),
                    timeZone: timeZone
                )
                if evaluation.isSuccess { completed += 1 }
            }
        }
        let continuity = ContinuitySnapshot(
            expectedCount: expected,
            completedCount: completed,
            currentStreak: 0
        )
        return MissionWriteResult(
            mission: mission,
            progress: ProgressCalculator.breakdown(
                from: contributions,
                continuity: expected == 0 ? nil : continuity
            ),
            effects: WriteEffects(
                sqliteCommitted: committed,
                cloudOutboxRecordNames: committed ? [SQLValue.uuid(mission.id)] : [],
                dryRun: dryRun
            )
        )
    }
}
