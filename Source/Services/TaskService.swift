import CalendarCountdownCore
import Foundation
import GRDB

public struct TaskWriteResult: Equatable, Codable, Sendable {
    public var series: TaskSeries
    public var occurrences: [TaskOccurrence]
    public var effects: WriteEffects
}

public struct MissionWriteResult: Equatable, Codable, Sendable {
    public var mission: MissionDefinition
    public var progress: MissionProgressBreakdown
    public var effects: WriteEffects
}

public struct HabitWriteResult: Equatable, Codable, Sendable {
    public var habit: HabitDefinition
    public var checkIn: CheckInRecord?
    public var period: HabitPeriod?
    public var stats: HabitStats?
    public var effects: WriteEffects
}

public struct TaskService: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func create(_ command: CreateTaskCommand, options: WriteOptions = WriteOptions()) throws -> TaskWriteResult {
        let series = try TaskSeries(
            title: command.title,
            markdownDescription: command.markdownDescription,
            kind: command.kind,
            missionID: command.missionID,
            priority: command.priority,
            workload: command.workload,
            schedule: command.schedule,
            recurrence: command.recurrence,
            alerts: command.alerts,
            projectionPolicy: command.projectionPolicy,
            createdAt: options.now,
            updatedAt: options.now,
            modifiedByDevice: db.deviceID
        ).validated()
        if let missionID = series.missionID {
            _ = try db.read { db in
                guard try DomainQueries.mission(db, id: missionID) != nil else {
                    throw DomainError.notFound(.missionNotFound, id: missionID)
                }
            }
        }
        let drafts = try Self.materialize(series: series, now: options.now)
        if options.dryRun {
            return TaskWriteResult(
                series: series,
                occurrences: drafts.map { Self.occurrence(from: $0, series: series, now: options.now, deviceID: db.deviceID) },
                effects: WriteEffects(
                    sqliteCommitted: false,
                    reminder: series.projectionPolicy.projectsReminder ? .planned("reminder") : .none,
                    event: series.projectionPolicy.projectsEvent ? .planned("event") : .none,
                    dryRun: true
                )
            )
        }

        let deviceID = db.deviceID
        return try db.write { db in
            let hash = try DomainWriter.payloadHash(command)
            if let ack = try DomainWriter.existingIdempotency(db, options: options, command: "tasks.create", payloadHash: hash),
               let existing = try DomainQueries.series(db, id: ack.objectID) {
                let occurrences = try DomainQueries.occurrences(forSeries: db, seriesID: existing.id)
                return TaskWriteResult(
                    series: existing,
                    occurrences: occurrences,
                    effects: WriteEffects(sqliteCommitted: true, cloudOutboxRecordNames: [SQLValue.uuid(existing.id)])
                )
            }

            try TaskSeriesRow(series).insert(db)
            var occurrences: [TaskOccurrence] = []
            for draft in drafts {
                let occurrence = Self.occurrence(from: draft, series: series, now: options.now, deviceID: deviceID)
                try TaskOccurrenceRow(occurrence).insert(db)
                try Self.enqueueOccurrence(db, occurrence: occurrence, operation: "upsert", now: options.now)
                occurrences.append(occurrence)
            }
            try Self.enqueueSeries(db, series: series, operation: "upsert", now: options.now)
            try DomainWriter.journal(
                db,
                options: options,
                command: "tasks.create",
                objectType: "task_series",
                objectID: series.id,
                before: nil,
                after: series.revision,
                summary: "新建任务：\(series.title)"
            )
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: "tasks.create",
                objectType: "task_series",
                objectID: series.id
            )
            try DomainWriter.rememberIdempotency(
                db,
                options: options,
                command: "tasks.create",
                payloadHash: hash,
                objectID: series.id,
                revision: series.revision
            )
            return TaskWriteResult(
                series: series,
                occurrences: occurrences,
                effects: WriteEffects(
                    sqliteCommitted: true,
                    cloudOutboxRecordNames: [SQLValue.uuid(series.id)] + occurrences.map { SQLValue.uuid($0.id) },
                    reminder: series.projectionPolicy.projectsReminder ? .planned("reminder") : .none,
                    event: series.projectionPolicy.projectsEvent ? .planned("event") : .none
                )
            )
        }
    }

    public func list(_ filter: TaskListFilter = TaskListFilter(), now: Date = Date()) throws -> [TaskOccurrenceView] {
        try db.read { db in
            let seriesByID = Dictionary(
                uniqueKeysWithValues: try DomainQueries.seriesList(db).map { ($0.id, $0) }
            )
            var occurrences = try TaskOccurrenceRow
                .filter(sql: "deleted_at IS NULL")
                .fetchAll(db)
                .map { try $0.domain() }
            if let missionID = filter.missionID {
                occurrences = occurrences.filter { seriesByID[$0.seriesID]?.missionID == missionID }
            }
            if filter.inboxOnly {
                occurrences = occurrences.filter { $0.plannedDue == nil && $0.plannedStart == nil && $0.status == .open }
            }
            if filter.openOnly {
                occurrences = occurrences.filter { $0.status == .open }
            }
            if filter.completedOnly {
                occurrences = occurrences.filter { $0.status == .completed }
            }
            if filter.overdueOnly {
                occurrences = occurrences.filter { $0.isOverdue(now: now) }
            }
            if let query = filter.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                occurrences = occurrences.filter { occurrence in
                    let title = occurrence.displayTitle(seriesTitle: seriesByID[occurrence.seriesID]?.title ?? "")
                    return title.localizedCaseInsensitiveContains(query)
                }
            }
            let views = occurrences.compactMap { occurrence -> TaskOccurrenceView? in
                guard let series = seriesByID[occurrence.seriesID] else { return nil }
                return TaskOccurrenceView(occurrence: occurrence, series: series)
            }
            .sorted { lhs, rhs in
                switch (lhs.occurrence.plannedDue, rhs.occurrence.plannedDue) {
                case let (l?, r?):
                    if l != r { return l < r }
                case (.none, .some):
                    return false
                case (.some, .none):
                    return true
                default:
                    break
                }
                return lhs.occurrence.id.uuidString < rhs.occurrence.id.uuidString
            }
            if let cursor = filter.cursor, let index = views.firstIndex(where: { $0.id.uuidString.lowercased() == cursor.lowercased() }) {
                return Array(views.dropFirst(index + 1).prefix(filter.limit))
            }
            return Array(views.prefix(max(1, filter.limit)))
        }
    }

    public func get(seriesID: UUID) throws -> TaskWriteResult {
        try db.read { db in
            guard let series = try DomainQueries.series(db, id: seriesID), series.deletedAt == nil else {
                throw DomainError.notFound(.taskNotFound, id: seriesID)
            }
            return TaskWriteResult(
                series: series,
                occurrences: try DomainQueries.occurrences(forSeries: db, seriesID: seriesID),
                effects: WriteEffects(sqliteCommitted: true)
            )
        }
    }

    public func occurrence(id: UUID) throws -> TaskOccurrenceView {
        try db.read { db in
            guard let occurrence = try DomainQueries.occurrence(db, id: id), occurrence.deletedAt == nil else {
                throw DomainError.notFound(.occurrenceNotFound, id: id)
            }
            guard let series = try DomainQueries.series(db, id: occurrence.seriesID) else {
                throw DomainError.notFound(.taskNotFound, id: occurrence.seriesID)
            }
            return TaskOccurrenceView(occurrence: occurrence, series: series)
        }
    }

    public func complete(occurrenceID: UUID, at completedAt: Date? = nil, options: WriteOptions = WriteOptions()) throws -> TaskWriteResult {
        try mutateOccurrence(
            occurrenceID: occurrenceID,
            options: options,
            command: "tasks.complete",
            mutation: .complete(completedAt ?? options.now)
        )
    }

    public func reopen(occurrenceID: UUID, options: WriteOptions = WriteOptions()) throws -> TaskWriteResult {
        try mutateOccurrence(
            occurrenceID: occurrenceID,
            options: options,
            command: "tasks.reopen",
            mutation: .reopen
        )
    }

    public func skip(occurrenceID: UUID, options: WriteOptions = WriteOptions()) throws -> TaskWriteResult {
        try mutateOccurrence(
            occurrenceID: occurrenceID,
            options: options,
            command: "tasks.skip",
            mutation: .skip
        )
    }

    public func archive(seriesID: UUID, options: WriteOptions = WriteOptions()) throws -> TaskWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var series = try DomainQueries.series(db, id: seriesID), series.deletedAt == nil else {
                throw DomainError.notFound(.taskNotFound, id: seriesID)
            }
            try DomainWriter.requireRevision(series.revision, options: options)
            if options.dryRun {
                return TaskWriteResult(
                    series: series,
                    occurrences: try DomainQueries.occurrences(forSeries: db, seriesID: seriesID),
                    effects: WriteEffects(sqliteCommitted: false, dryRun: true)
                )
            }
            let before = series.revision
            series.deletedAt = options.now
            series.updatedAt = options.now
            series.revision += 1
            series.modifiedByDevice = deviceID
            try TaskSeriesRow(series).update(db)
            var occurrences = try DomainQueries.occurrences(forSeries: db, seriesID: seriesID)
            for index in occurrences.indices {
                occurrences[index].disposition = .archived
                occurrences[index].updatedAt = options.now
                occurrences[index].revision += 1
                try TaskOccurrenceRow(occurrences[index]).update(db)
            }
            try Self.enqueueSeries(db, series: series, operation: "upsert", now: options.now)
            try DomainWriter.journal(
                db,
                options: options,
                command: "tasks.archive",
                objectType: "task_series",
                objectID: series.id,
                before: before,
                after: series.revision,
                summary: "归档任务：\(series.title)"
            )
            return TaskWriteResult(
                series: series,
                occurrences: occurrences,
                effects: WriteEffects(sqliteCommitted: true, cloudOutboxRecordNames: [SQLValue.uuid(series.id)])
            )
        }
    }

    public func delete(seriesID: UUID, permanent: Bool, confirmID: UUID?, options: WriteOptions = WriteOptions()) throws -> TaskWriteResult {
        if permanent {
            guard confirmID == seriesID else {
                throw DomainError.validation("永久删除必须提供 --confirm-id。")
            }
        }
        if !permanent {
            return try archive(seriesID: seriesID, options: options)
        }
        let deviceID = db.deviceID
        return try db.write { db in
            guard var series = try DomainQueries.series(db, id: seriesID) else {
                throw DomainError.notFound(.taskNotFound, id: seriesID)
            }
            var occurrences = try DomainQueries.occurrences(forSeries: db, seriesID: seriesID)
            if options.dryRun {
                return TaskWriteResult(
                    series: series,
                    occurrences: occurrences,
                    effects: WriteEffects(sqliteCommitted: false, dryRun: true)
                )
            }
            let before = series.revision
            series.deletedAt = options.now
            series.updatedAt = options.now
            series.revision += 1
            series.modifiedByDevice = deviceID
            try TaskSeriesRow(series).update(db)
            for index in occurrences.indices {
                occurrences[index].deletedAt = options.now
                occurrences[index].updatedAt = options.now
                occurrences[index].revision += 1
                occurrences[index].modifiedByDevice = deviceID
                try TaskOccurrenceRow(occurrences[index]).update(db)
                try DomainWriter.enqueueEncoded(
                    db,
                    recordType: "CDTaskOccurrence",
                    recordName: occurrences[index].id,
                    operation: "delete",
                    revision: occurrences[index].revision,
                    payload: occurrences[index],
                    modifiedByDevice: deviceID,
                    updatedAt: occurrences[index].updatedAt,
                    deletedAt: occurrences[index].deletedAt,
                    now: options.now
                )
            }
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDTaskSeries",
                recordName: series.id,
                operation: "delete",
                revision: series.revision,
                payload: series,
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "task_series",
                    objectID: series.id,
                    values: ["title": series.title, "description_md": series.markdownDescription],
                    deviceID: deviceID,
                    now: options.now
                ),
                modifiedByDevice: deviceID,
                updatedAt: series.updatedAt,
                deletedAt: series.deletedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "tasks.delete",
                objectType: "task_series",
                objectID: seriesID,
                before: before,
                after: series.revision,
                summary: "删除任务：\(series.title)"
            )
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: "tasks.delete",
                objectType: "task_series",
                objectID: series.id
            )
            return TaskWriteResult(
                series: series,
                occurrences: occurrences,
                effects: WriteEffects(
                    sqliteCommitted: true,
                    cloudOutboxRecordNames: [SQLValue.uuid(series.id)] + occurrences.map { SQLValue.uuid($0.id) },
                    reminder: .planned("remove"),
                    event: .planned("remove")
                )
            )
        }
    }

    public func patch(
        occurrenceID: UUID,
        command: PatchTaskCommand,
        options: WriteOptions = WriteOptions()
    ) throws -> TaskWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var occurrence = try DomainQueries.occurrence(db, id: occurrenceID), occurrence.deletedAt == nil else {
                throw DomainError.notFound(.occurrenceNotFound, id: occurrenceID)
            }
            guard var series = try DomainQueries.series(db, id: occurrence.seriesID), series.deletedAt == nil else {
                throw DomainError.notFound(.taskNotFound, id: occurrence.seriesID)
            }
            try DomainWriter.requireRevision(occurrence.revision, options: options)
            if options.dryRun {
                return TaskWriteResult(
                    series: series,
                    occurrences: try DomainQueries.occurrences(forSeries: db, seriesID: series.id),
                    effects: WriteEffects(sqliteCommitted: false, dryRun: true)
                )
            }
            switch command.scope {
            case .thisOccurrence:
                try Self.applyOccurrencePatch(
                    command,
                    occurrence: &occurrence,
                    series: series,
                    db: db,
                    options: options,
                    deviceID: deviceID
                )
            case .series:
                try Self.applySeriesPatch(
                    command,
                    series: &series,
                    db: db,
                    options: options,
                    deviceID: deviceID,
                    splitFrom: nil
                )
            case .thisAndFuture:
                if series.recurrence == nil {
                    try Self.applySeriesPatch(
                        command,
                        series: &series,
                        db: db,
                        options: options,
                        deviceID: deviceID,
                        splitFrom: nil
                    )
                } else {
                    try Self.splitFuture(
                        command,
                        occurrence: occurrence,
                        series: &series,
                        db: db,
                        options: options,
                        deviceID: deviceID
                    )
                }
            }
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: "tasks.update",
                objectType: "task_series",
                objectID: series.id
            )
            let latest = try DomainQueries.series(db, id: series.id) ?? series
            return TaskWriteResult(
                series: latest,
                occurrences: try DomainQueries.occurrences(forSeries: db, seriesID: latest.id),
                effects: WriteEffects(
                    sqliteCommitted: true,
                    cloudOutboxRecordNames: [SQLValue.uuid(latest.id)],
                    reminder: latest.projectionPolicy.projectsReminder ? .planned("reminder") : .none,
                    event: latest.projectionPolicy.projectsEvent ? .planned("event") : .none
                )
            )
        }
    }

    private enum OccurrenceMutation: Sendable {
        case complete(Date)
        case reopen
        case skip
    }

    private func mutateOccurrence(
        occurrenceID: UUID,
        options: WriteOptions,
        command: String,
        mutation: OccurrenceMutation
    ) throws -> TaskWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var occurrence = try DomainQueries.occurrence(db, id: occurrenceID), occurrence.deletedAt == nil else {
                throw DomainError.notFound(.occurrenceNotFound, id: occurrenceID)
            }
            guard let series = try DomainQueries.series(db, id: occurrence.seriesID), series.deletedAt == nil else {
                throw DomainError.notFound(.taskNotFound, id: occurrence.seriesID)
            }
            try DomainWriter.requireRevision(occurrence.revision, options: options)
            if options.dryRun {
                return TaskWriteResult(
                    series: series,
                    occurrences: try DomainQueries.occurrences(forSeries: db, seriesID: series.id),
                    effects: WriteEffects(sqliteCommitted: false, dryRun: true)
                )
            }
            let before = occurrence.revision
            switch mutation {
            case let .complete(completedAt):
                guard occurrence.status == .open else {
                    throw DomainError.validation("只能完成未完成的任务实例。")
                }
                occurrence.status = .completed
                occurrence.completedAt = completedAt
                try Self.appendAfterCompletionIfNeeded(
                    series: series,
                    completedOccurrence: occurrence,
                    db: db,
                    options: options,
                    deviceID: deviceID
                )
            case .reopen:
                occurrence.status = .open
                occurrence.completedAt = nil
            case .skip:
                guard series.recurrence != nil else {
                    throw DomainError.validation("只有循环实例可以跳过。")
                }
                guard occurrence.status == .open else {
                    throw DomainError.validation("只能跳过未完成的任务实例。")
                }
                occurrence.status = .skipped
                try Self.appendAfterCompletionIfNeeded(
                    series: series,
                    completedOccurrence: occurrence,
                    db: db,
                    options: options,
                    deviceID: deviceID
                )
            }
            occurrence.updatedAt = options.now
            occurrence.revision += 1
            occurrence.modifiedByDevice = deviceID
            try TaskOccurrenceRow(occurrence).update(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDTaskOccurrence",
                recordName: occurrence.id,
                operation: "upsert",
                revision: occurrence.revision,
                payload: occurrence,
                fields: try DomainWriter.fieldSnapshots(
                    db,
                    objectType: "task_occurrence",
                    objectID: occurrence.id,
                    values: ["status": occurrence.status.rawValue, "title": occurrence.titleOverride],
                    deviceID: deviceID,
                    now: options.now
                ),
                modifiedByDevice: deviceID,
                updatedAt: occurrence.updatedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: command,
                objectType: "task_occurrence",
                objectID: occurrence.id,
                before: before,
                after: occurrence.revision,
                summary: Self.mutationSummary(
                    command: command,
                    title: occurrence.displayTitle(seriesTitle: series.title)
                )
            )
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: command,
                objectType: "task_occurrence",
                objectID: occurrence.id
            )
            return TaskWriteResult(
                series: series,
                occurrences: try DomainQueries.occurrences(forSeries: db, seriesID: series.id),
                effects: WriteEffects(
                    sqliteCommitted: true,
                    cloudOutboxRecordNames: [SQLValue.uuid(occurrence.id)],
                    reminder: series.projectionPolicy.projectsReminder ? .planned("reminder") : .none,
                    event: series.projectionPolicy.projectsEvent ? .planned("event") : .none
                )
            )
        }
    }

    private static func appendAfterCompletionIfNeeded(
        series: TaskSeries,
        completedOccurrence: TaskOccurrence,
        db: Database,
        options: WriteOptions,
        deviceID: UUID
    ) throws {
        guard let spec = series.recurrence, spec.mode == .afterCompletion else { return }
        let existing = try DomainQueries.occurrences(forSeries: db, seriesID: series.id)
        if let count = spec.plannedCount, existing.count >= count {
            return
        }
        let anchor = completedOccurrence.completedAt ?? options.now
        guard let nextDue = try RecurrenceEngine.nextAfterCompletion(
            spec: spec,
            completedAt: anchor,
            previousDue: completedOccurrence.plannedDue
        ) else {
            return
        }
        let duration: TimeInterval?
        if let start = completedOccurrence.plannedStart, let due = completedOccurrence.plannedDue {
            duration = due.timeIntervalSince(start)
        } else {
            duration = nil
        }
        let draft = PlannedOccurrenceDraft(
            occurrenceKey: RecurrenceEngine.occurrenceKey(seriesID: series.id, plannedDue: nextDue),
            plannedStart: duration.map { nextDue.addingTimeInterval(-$0) },
            plannedDue: nextDue
        )
        if existing.contains(where: { $0.occurrenceKey == draft.occurrenceKey }) {
            return
        }
        let occurrence = Self.occurrence(from: draft, series: series, now: options.now, deviceID: deviceID)
        try TaskOccurrenceRow(occurrence).insert(db)
        try Self.enqueueOccurrence(db, occurrence: occurrence, operation: "upsert", now: options.now)
    }

    private static func mutationSummary(command: String, title: String) -> String {
        switch command {
        case "tasks.complete": "完成任务：\(title)"
        case "tasks.reopen": "重新打开任务：\(title)"
        case "tasks.skip": "跳过任务：\(title)"
        default: "更新任务：\(title)"
        }
    }

    static func materialize(series: TaskSeries, now: Date) throws -> [PlannedOccurrenceDraft] {
        if let recurrence = series.recurrence, let due = series.schedule.plannedDue {
            switch recurrence.mode {
            case .fixedSchedule:
                return try RecurrenceEngine.materializeFixedSchedule(
                    seriesID: series.id,
                    spec: recurrence,
                    firstDue: due,
                    firstStart: series.schedule.plannedStart,
                    now: now
                )
            case .afterCompletion:
                return [
                    PlannedOccurrenceDraft(
                        occurrenceKey: RecurrenceEngine.occurrenceKey(seriesID: series.id, plannedDue: due),
                        plannedStart: series.schedule.plannedStart,
                        plannedDue: due
                    )
                ]
            }
        }
        if series.schedule.isUndated {
            return [
                PlannedOccurrenceDraft(
                    occurrenceKey: RecurrenceEngine.undatedOccurrenceKey(seriesID: series.id),
                    plannedStart: nil,
                    plannedDue: Date.distantFuture.addingTimeInterval(-1)
                )
            ]
        }
        let due = series.schedule.plannedDue ?? series.schedule.plannedStart ?? now
        return [
            PlannedOccurrenceDraft(
                occurrenceKey: RecurrenceEngine.occurrenceKey(seriesID: series.id, plannedDue: due),
                plannedStart: series.schedule.plannedStart,
                plannedDue: due
            )
        ]
    }

    static func occurrence(
        from draft: PlannedOccurrenceDraft,
        series: TaskSeries,
        now: Date,
        deviceID: UUID
    ) -> TaskOccurrence {
        let undated = draft.occurrenceKey.hasSuffix("@undated")
        return TaskOccurrence(
            seriesID: series.id,
            occurrenceKey: draft.occurrenceKey,
            plannedStart: undated ? nil : draft.plannedStart,
            plannedDue: undated ? nil : draft.plannedDue,
            createdAt: now,
            updatedAt: now,
            modifiedByDevice: deviceID
        )
    }

    static func enqueueSeries(
        _ db: Database,
        series: TaskSeries,
        operation: String,
        now: Date
    ) throws {
        try DomainWriter.enqueueEncoded(
            db,
            recordType: "CDTaskSeries",
            recordName: series.id,
            operation: operation,
            revision: series.revision,
            payload: series,
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
            deletedAt: series.deletedAt,
            now: now
        )
    }

    static func enqueueOccurrence(
        _ db: Database,
        occurrence: TaskOccurrence,
        operation: String,
        now: Date
    ) throws {
        try DomainWriter.enqueueEncoded(
            db,
            recordType: "CDTaskOccurrence",
            recordName: occurrence.id,
            operation: operation,
            revision: occurrence.revision,
            payload: occurrence,
            fields: try DomainWriter.fieldSnapshots(
                db,
                objectType: "task_occurrence",
                objectID: occurrence.id,
                values: ["status": occurrence.status.rawValue, "title": occurrence.titleOverride],
                deviceID: occurrence.modifiedByDevice,
                now: occurrence.updatedAt
            ),
            modifiedByDevice: occurrence.modifiedByDevice,
            updatedAt: occurrence.updatedAt,
            deletedAt: occurrence.deletedAt,
            now: now
        )
    }

    private static func applyOccurrencePatch(
        _ command: PatchTaskCommand,
        occurrence: inout TaskOccurrence,
        series: TaskSeries,
        db: Database,
        options: WriteOptions,
        deviceID: UUID
    ) throws {
        let before = occurrence.revision
        if let title = command.title { occurrence.titleOverride = title }
        if let markdown = command.markdownDescription { occurrence.descriptionOverrideMarkdown = markdown }
        if let schedule = command.schedule {
            occurrence.plannedStart = schedule.plannedStart
            occurrence.plannedDue = schedule.plannedDue
        }
        occurrence.updatedAt = options.now
        occurrence.revision += 1
        occurrence.modifiedByDevice = deviceID
        try TaskOccurrenceRow(occurrence).update(db)
        try enqueueOccurrence(db, occurrence: occurrence, operation: "upsert", now: options.now)
        try DomainWriter.journal(
            db,
            options: options,
            command: "tasks.update",
            objectType: "task_occurrence",
            objectID: occurrence.id,
            before: before,
            after: occurrence.revision,
            summary: "编辑任务：\(occurrence.displayTitle(seriesTitle: series.title))"
        )
        _ = series
    }

    private static func applySeriesPatch(
        _ command: PatchTaskCommand,
        series: inout TaskSeries,
        db: Database,
        options: WriteOptions,
        deviceID: UUID,
        splitFrom: TaskOccurrence?
    ) throws {
        let before = series.revision
        if let title = command.title { series.title = title }
        if let markdown = command.markdownDescription { series.markdownDescription = markdown }
        if let kind = command.kind { series.kind = kind }
        if command.clearMission == true {
            series.missionID = nil
        } else if let missionID = command.missionID {
            series.missionID = missionID
        }
        if let priority = command.priority { series.priority = priority }
        if let workload = command.workload { series.workload = workload }
        if let schedule = command.schedule { series.schedule = schedule }
        if command.clearRecurrence == true {
            series.recurrence = nil
        } else if let recurrence = command.recurrence {
            series.recurrence = recurrence
        }
        if let alerts = command.alerts { series.alerts = alerts }
        if let policy = command.projectionPolicy { series.projectionPolicy = policy }
        series.updatedAt = options.now
        series.revision += 1
        series.modifiedByDevice = deviceID
        series = try series.validated()
        try TaskSeriesRow(series).update(db)
        try DomainWriter.touchFields(
            db,
            objectType: "task_series",
            objectID: series.id,
            fields: ["title", "description_md"],
            deviceID: deviceID,
            now: options.now
        )
        try enqueueSeries(db, series: series, operation: "upsert", now: options.now)

        if command.schedule != nil || command.recurrence != nil || command.clearRecurrence == true {
            try rematerializeOpenOccurrences(
                series: series,
                db: db,
                options: options,
                deviceID: deviceID,
                migrateHistory: command.migrateHistory,
                keepOccurrenceID: splitFrom?.id
            )
        }
        try DomainWriter.journal(
            db,
            options: options,
            command: "tasks.update",
            objectType: "task_series",
            objectID: series.id,
            before: before,
            after: series.revision,
            summary: "编辑任务：\(series.title)"
        )
    }

    private static func rematerializeOpenOccurrences(
        series: TaskSeries,
        db: Database,
        options: WriteOptions,
        deviceID: UUID,
        migrateHistory: Bool,
        keepOccurrenceID: UUID?
    ) throws {
        let existing = try DomainQueries.occurrences(forSeries: db, seriesID: series.id)
        let drafts = try materialize(series: series, now: options.now)
        let draftKeys = Set(drafts.map(\.occurrenceKey))
        for draft in drafts {
            if let index = existing.firstIndex(where: { $0.occurrenceKey == draft.occurrenceKey }) {
                var occurrence = existing[index]
                if occurrence.status == .open || migrateHistory {
                    occurrence.plannedStart = draft.plannedStart
                    occurrence.plannedDue = draft.occurrenceKey.hasSuffix("@undated") ? nil : draft.plannedDue
                    occurrence.updatedAt = options.now
                    occurrence.revision += 1
                    occurrence.modifiedByDevice = deviceID
                    try TaskOccurrenceRow(occurrence).update(db)
                    try enqueueOccurrence(db, occurrence: occurrence, operation: "upsert", now: options.now)
                }
            } else {
                let occurrence = Self.occurrence(from: draft, series: series, now: options.now, deviceID: deviceID)
                try TaskOccurrenceRow(occurrence).insert(db)
                try enqueueOccurrence(db, occurrence: occurrence, operation: "upsert", now: options.now)
            }
        }
        for var leftover in existing where leftover.status == .open && !draftKeys.contains(leftover.occurrenceKey) {
            if leftover.id == keepOccurrenceID { continue }
            leftover.deletedAt = options.now
            leftover.updatedAt = options.now
            leftover.revision += 1
            leftover.modifiedByDevice = deviceID
            try TaskOccurrenceRow(leftover).update(db)
            try enqueueOccurrence(db, occurrence: leftover, operation: "delete", now: options.now)
        }
    }

    private static func splitFuture(
        _ command: PatchTaskCommand,
        occurrence: TaskOccurrence,
        series: inout TaskSeries,
        db: Database,
        options: WriteOptions,
        deviceID: UUID
    ) throws {
        var existing = try DomainQueries.occurrences(forSeries: db, seriesID: series.id)
        for index in existing.indices {
            let item = existing[index]
            guard item.status == .open, item.id != occurrence.id else { continue }
            if let due = item.plannedDue, let anchor = occurrence.plannedDue, due < anchor {
                continue
            }
            existing[index].deletedAt = options.now
            existing[index].updatedAt = options.now
            existing[index].revision += 1
            existing[index].modifiedByDevice = deviceID
            try TaskOccurrenceRow(existing[index]).update(db)
            try enqueueOccurrence(db, occurrence: existing[index], operation: "delete", now: options.now)
        }
        if var recurrence = series.recurrence, let due = occurrence.plannedDue {
            recurrence.end = .onDate(LocalDate.from(due, timeZone: TimeZone(identifier: series.schedule.timeZoneIdentifier) ?? .current))
            series.recurrence = recurrence
        }
        series.updatedAt = options.now
        series.revision += 1
        series.modifiedByDevice = deviceID
        try TaskSeriesRow(series).update(db)
        try enqueueSeries(db, series: series, operation: "upsert", now: options.now)

        var next = series
        next.id = UUID()
        next.createdAt = options.now
        next.updatedAt = options.now
        next.revision = 1
        next.modifiedByDevice = deviceID
        next.deletedAt = nil
        if let title = command.title { next.title = title }
        if let markdown = command.markdownDescription { next.markdownDescription = markdown }
        if let kind = command.kind { next.kind = kind }
        if let priority = command.priority { next.priority = priority }
        if let workload = command.workload { next.workload = workload }
        if let schedule = command.schedule {
            next.schedule = schedule
        } else {
            next.schedule.plannedStart = occurrence.plannedStart
            next.schedule.plannedDue = occurrence.plannedDue
        }
        if command.clearRecurrence == true {
            next.recurrence = nil
        } else if let recurrence = command.recurrence {
            next.recurrence = recurrence
        }
        if let alerts = command.alerts { next.alerts = alerts }
        if let policy = command.projectionPolicy { next.projectionPolicy = policy }
        next = try next.validated()
        try TaskSeriesRow(next).insert(db)
        try enqueueSeries(db, series: next, operation: "upsert", now: options.now)
        let drafts = try materialize(series: next, now: options.now)
        for draft in drafts {
            let created = Self.occurrence(from: draft, series: next, now: options.now, deviceID: deviceID)
            try TaskOccurrenceRow(created).insert(db)
            try enqueueOccurrence(db, occurrence: created, operation: "upsert", now: options.now)
        }
        series = next
    }
}
