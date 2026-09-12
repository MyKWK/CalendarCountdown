import CalendarCountdownCore
import Foundation
import GRDB

public struct HabitService: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func create(_ command: CreateHabitCommand, options: WriteOptions = WriteOptions()) throws -> HabitWriteResult {
        let habit = try HabitDefinition(
            title: command.title,
            markdownDescription: command.markdownDescription,
            metric: command.metric,
            targetValue: command.targetValue,
            unit: command.unit,
            schedule: command.schedule,
            activeFrom: command.activeFrom,
            activeUntil: command.activeUntil,
            reminderTimes: command.reminderTimes,
            allowBackfillDays: command.allowBackfillDays,
            completionPolicy: command.completionPolicy,
            projectionPolicy: command.projectionPolicy,
            missionID: command.missionID,
            createdAt: options.now,
            updatedAt: options.now,
            modifiedByDevice: db.deviceID
        ).validated()
        if options.dryRun {
            return HabitWriteResult(
                habit: habit,
                effects: WriteEffects(sqliteCommitted: false, dryRun: true)
            )
        }
        return try db.write { db in
            let hash = try DomainWriter.payloadHash(command)
            if let ack = try DomainWriter.existingIdempotency(db, options: options, command: "habits.create", payloadHash: hash),
               let existing = try DomainQueries.habit(db, id: ack.objectID) {
            return try Self.result(existing, db: db, committed: true, outboxNames: [SQLValue.uuid(existing.id)])
            }
            try HabitRow(habit).insert(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDHabit",
                recordName: habit.id,
                operation: "upsert",
                revision: habit.revision,
                payload: habit,
                modifiedByDevice: habit.modifiedByDevice,
                updatedAt: habit.updatedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "habits.create",
                objectType: "habit",
                objectID: habit.id,
                before: nil,
                after: habit.revision,
                summary: "created"
            )
            try DomainWriter.rememberIdempotency(
                db,
                options: options,
                command: "habits.create",
                payloadHash: hash,
                objectID: habit.id,
                revision: habit.revision
            )
            return try Self.result(habit, db: db, committed: true, outboxNames: [SQLValue.uuid(habit.id)])
        }
    }

    public func list() throws -> [HabitWriteResult] {
        try db.read { db in
            try DomainQueries.habits(db).map { try Self.result($0, db: db, committed: true) }
        }
    }

    public func get(id: UUID) throws -> HabitWriteResult {
        try db.read { db in
            guard let habit = try DomainQueries.habit(db, id: id), habit.deletedAt == nil else {
                throw DomainError.notFound(.habitNotFound, id: id)
            }
            return try Self.result(habit, db: db, committed: true)
        }
    }

    public func checkIn(
        habitID: UUID,
        value: Decimal? = nil,
        at effectiveAt: Date? = nil,
        fillToTarget: Bool = false,
        note: String? = nil,
        source: CheckInSource = .app,
        options: WriteOptions = WriteOptions()
    ) throws -> HabitWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard let habit = try DomainQueries.habit(db, id: habitID), habit.deletedAt == nil else {
                throw DomainError.notFound(.habitNotFound, id: habitID)
            }
            let timeZone = TimeZone.current
            let when = effectiveAt ?? options.now
            if let earliest = Calendar.current.date(byAdding: .day, value: -habit.allowBackfillDays, to: options.now),
               when < earliest {
                throw DomainError.validation("超出允许的补打天数。")
            }
            guard let periodKey = HabitStatisticsEngine.periodKey(
                for: when,
                schedule: habit.schedule,
                timeZone: timeZone
            ) else {
                throw DomainError.validation("这一天不是该习惯的计划日。")
            }
            let existing = try DomainQueries.checkIns(db, habitID: habit.id)
            let live = existing.filter { $0.deletedAt == nil && $0.periodKey == periodKey }
            let current = live.reduce(Decimal(0)) { $0 + $1.value }
            let increment: Decimal
            if fillToTarget {
                increment = HabitStatisticsEngine.remainingToTarget(target: habit.targetValue, actual: current)
            } else {
                increment = value ?? habit.defaultIncrement
            }
            guard increment > 0 else {
                throw DomainError.validation("本次打卡数值必须大于 0。")
            }
            if options.dryRun {
                return try Self.result(habit, db: db, committed: false, dryRun: true)
            }
            let record = CheckInRecord(
                habitID: habit.id,
                periodKey: periodKey,
                value: increment,
                unit: habit.unit,
                effectiveAt: when,
                recordedAt: options.now,
                source: source,
                note: note,
                createdAt: options.now,
                updatedAt: options.now,
                modifiedByDevice: deviceID
            )
            try CheckInRow(record).insert(db)
            var period = try DomainQueries.periods(db, habitID: habit.id).first(where: { $0.periodKey == periodKey })
                ?? HabitPeriod(
                    habitID: habit.id,
                    periodKey: periodKey,
                    targetValueSnapshot: habit.targetValue,
                    modifiedByDevice: deviceID
                )
            let evaluation = HabitStatisticsEngine.evaluate(
                habit: habit,
                periodKey: periodKey,
                checkIns: existing + [record],
                period: period,
                timeZone: timeZone
            )
            if evaluation.isSuccess {
                period.disposition = .completed
                period.completedAt = options.now
            }
            period.updatedAt = options.now
            period.revision += period.revision == 1 && period.completedAt == nil && !evaluation.isSuccess ? 0 : 1
            period.modifiedByDevice = deviceID
            try HabitPeriodRow(period).save(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDCheckIn",
                recordName: record.id,
                operation: "upsert",
                revision: record.revision,
                payload: record,
                modifiedByDevice: deviceID,
                updatedAt: record.updatedAt,
                now: options.now
            )
            try Self.enqueuePeriod(db, period: period, now: options.now)
            try DomainWriter.journal(
                db,
                options: options,
                command: "habits.checkin",
                objectType: "checkin",
                objectID: record.id,
                before: nil,
                after: record.revision,
                summary: periodKey
            )
            var write = try Self.result(
                habit,
                db: db,
                committed: true,
                outboxNames: [SQLValue.uuid(record.id), SQLValue.uuid(Self.periodRecordName(period))]
            )
            write.checkIn = record
            write.period = period
            write.effects.reminder = habit.projectionPolicy.projectsReminder ? .planned("reminder") : .none
            return write
        }
    }

    public func undoCheckIn(id: UUID, options: WriteOptions = WriteOptions()) throws -> HabitWriteResult {
        return try db.write { db in
            guard var record = try DomainQueries.checkIn(db, id: id), record.deletedAt == nil else {
                throw DomainError.notFound(.checkInNotFound, id: id)
            }
            try DomainWriter.requireRevision(record.revision, options: options)
            guard let habit = try DomainQueries.habit(db, id: record.habitID) else {
                throw DomainError.notFound(.habitNotFound, id: record.habitID)
            }
            if options.dryRun {
                return try Self.result(habit, db: db, committed: false, dryRun: true)
            }
            record.deletedAt = options.now
            record.updatedAt = options.now
            record.revision += 1
            try CheckInRow(record).update(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDCheckIn",
                recordName: record.id,
                operation: "upsert",
                revision: record.revision,
                payload: record,
                modifiedByDevice: record.modifiedByDevice,
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt,
                now: options.now
            )
            let remaining = try DomainQueries.checkIns(db, habitID: habit.id)
            var period = try DomainQueries.periods(db, habitID: habit.id).first(where: { $0.periodKey == record.periodKey })
            if var current = period {
                let evaluation = HabitStatisticsEngine.evaluate(
                    habit: habit,
                    periodKey: record.periodKey,
                    checkIns: remaining,
                    period: current,
                    timeZone: TimeZone.current
                )
                if current.disposition != .skipped {
                    current.disposition = evaluation.isSuccess ? .completed : .open
                    current.completedAt = evaluation.isSuccess ? current.completedAt ?? options.now : nil
                    current.updatedAt = options.now
                    current.revision += 1
                    current.modifiedByDevice = record.modifiedByDevice
                    try HabitPeriodRow(current).save(db)
                    try Self.enqueuePeriod(db, period: current, now: options.now)
                    period = current
                }
            }
            try DomainWriter.journal(
                db,
                options: options,
                command: "habits.undo-checkin",
                objectType: "checkin",
                objectID: record.id,
                before: record.revision - 1,
                after: record.revision,
                summary: "tombstone"
            )
            var write = try Self.result(
                habit,
                db: db,
                committed: true,
                outboxNames: [SQLValue.uuid(record.id)] + (period.map { [SQLValue.uuid(Self.periodRecordName($0))] } ?? [])
            )
            write.checkIn = record
            write.period = period
            return write
        }
    }

    public func skipPeriod(habitID: UUID, periodKey: String, options: WriteOptions = WriteOptions()) throws -> HabitWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard let habit = try DomainQueries.habit(db, id: habitID), habit.deletedAt == nil else {
                throw DomainError.notFound(.habitNotFound, id: habitID)
            }
            if options.dryRun {
                return try Self.result(habit, db: db, committed: false, dryRun: true)
            }
            var period = try DomainQueries.periods(db, habitID: habit.id).first(where: { $0.periodKey == periodKey })
                ?? HabitPeriod(
                    habitID: habit.id,
                    periodKey: periodKey,
                    targetValueSnapshot: habit.targetValue,
                    modifiedByDevice: deviceID
                )
            period.disposition = .skipped
            period.updatedAt = options.now
            period.revision += 1
            period.modifiedByDevice = deviceID
            try HabitPeriodRow(period).save(db)
            try Self.enqueuePeriod(db, period: period, now: options.now)
            try DomainWriter.journal(
                db,
                options: options,
                command: "habits.skip",
                objectType: "habit_period",
                objectID: Self.periodRecordName(period),
                before: period.revision - 1,
                after: period.revision,
                summary: periodKey
            )
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: "habits.skip",
                objectType: "habit",
                objectID: habit.id
            )
            var write = try Self.result(
                habit,
                db: db,
                committed: true,
                outboxNames: [SQLValue.uuid(Self.periodRecordName(period))]
            )
            write.period = period
            return write
        }
    }

    public func update(id: UUID, command: PatchHabitCommand, options: WriteOptions = WriteOptions()) throws -> HabitWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var habit = try DomainQueries.habit(db, id: id), habit.deletedAt == nil else {
                throw DomainError.notFound(.habitNotFound, id: id)
            }
            try DomainWriter.requireRevision(habit.revision, options: options)
            if options.dryRun {
                return try Self.result(habit, db: db, committed: false, dryRun: true)
            }
            let before = habit.revision
            if let title = command.title { habit.title = title }
            if let markdown = command.markdownDescription { habit.markdownDescription = markdown }
            if let target = command.targetValue { habit.targetValue = target }
            if let unit = command.unit { habit.unit = unit }
            if let schedule = command.schedule { habit.schedule = schedule }
            if let reminders = command.reminderTimes { habit.reminderTimes = reminders }
            if let days = command.allowBackfillDays { habit.allowBackfillDays = days }
            if let policy = command.completionPolicy { habit.completionPolicy = policy }
            if let projection = command.projectionPolicy { habit.projectionPolicy = projection }
            if command.clearActiveUntil == true {
                habit.activeUntil = nil
            } else if let until = command.activeUntil {
                habit.activeUntil = until
            }
            habit.updatedAt = options.now
            habit.revision += 1
            habit.modifiedByDevice = deviceID
            habit = try habit.validated()
            try HabitRow(habit).update(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDHabit",
                recordName: habit.id,
                operation: "upsert",
                revision: habit.revision,
                payload: habit,
                modifiedByDevice: deviceID,
                updatedAt: habit.updatedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: "habits.update",
                objectType: "habit",
                objectID: habit.id,
                before: before,
                after: habit.revision,
                summary: "updated"
            )
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: "habits.update",
                objectType: "habit",
                objectID: habit.id
            )
            return try Self.result(habit, db: db, committed: true, outboxNames: [SQLValue.uuid(habit.id)])
        }
    }

    public func archive(id: UUID, options: WriteOptions = WriteOptions()) throws -> HabitWriteResult {
        try tombstone(id: id, permanent: false, options: options)
    }

    public func delete(id: UUID, permanent: Bool, confirmID: UUID?, options: WriteOptions = WriteOptions()) throws -> HabitWriteResult {
        if permanent {
            guard confirmID == id else {
                throw DomainError.validation("永久删除必须提供 --confirm-id。")
            }
        }
        return try tombstone(id: id, permanent: true, options: options)
    }

    private func tombstone(id: UUID, permanent: Bool, options: WriteOptions) throws -> HabitWriteResult {
        let deviceID = db.deviceID
        return try db.write { db in
            guard var habit = try DomainQueries.habit(db, id: id) else {
                throw DomainError.notFound(.habitNotFound, id: id)
            }
            if options.dryRun {
                return try Self.result(habit, db: db, committed: false, dryRun: true)
            }
            let before = habit.revision
            habit.deletedAt = options.now
            habit.updatedAt = options.now
            habit.revision += 1
            habit.modifiedByDevice = deviceID
            try HabitRow(habit).update(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDHabit",
                recordName: habit.id,
                operation: "delete",
                revision: habit.revision,
                payload: habit,
                modifiedByDevice: deviceID,
                updatedAt: habit.updatedAt,
                deletedAt: habit.deletedAt,
                now: options.now
            )
            try DomainWriter.journal(
                db,
                options: options,
                command: permanent ? "habits.delete" : "habits.archive",
                objectType: "habit",
                objectID: habit.id,
                before: before,
                after: habit.revision,
                summary: "tombstone"
            )
            try DomainWriter.pendingProjection(
                db,
                options: options,
                command: "habits.delete",
                objectType: "habit",
                objectID: habit.id
            )
            return try Self.result(habit, db: db, committed: true, outboxNames: [SQLValue.uuid(habit.id)])
        }
    }

    public func stats(id: UUID, from: LocalDate? = nil, to: LocalDate? = nil) throws -> HabitStats {
        try get(id: id).stats ?? HabitStats(
            currentStreak: 0,
            longestStreak: 0,
            weekCompletionRate: nil,
            monthCompletionRate: nil,
            totalValue: 0,
            averageValue: 0,
            heatMap: [:]
        )
    }

    private static func enqueuePeriod(_ db: Database, period: HabitPeriod, now: Date) throws {
        try DomainWriter.enqueueEncoded(
            db,
            recordType: "CDHabitPeriod",
            recordName: periodRecordName(period),
            operation: "upsert",
            revision: period.revision,
            payload: period,
            modifiedByDevice: period.modifiedByDevice,
            updatedAt: period.updatedAt,
            deletedAt: period.deletedAt,
            now: now
        )
    }

    static func periodRecordName(_ period: HabitPeriod) -> UUID {
        CloudRecordIdentity.habitPeriod(habitID: period.habitID, periodKey: period.periodKey)
    }

    private static func result(
        _ habit: HabitDefinition,
        db: Database,
        committed: Bool,
        dryRun: Bool = false,
        outboxNames: [String] = []
    ) throws -> HabitWriteResult {
        let timeZone = TimeZone.current
        let checkIns = try DomainQueries.checkIns(db, habitID: habit.id)
        let storedPeriods = try DomainQueries.periods(db, habitID: habit.id)
        let start = habit.activeFrom
        let end = LocalDate.from(Date(), timeZone: timeZone)
        let keys = HabitStatisticsEngine.expectedPeriodKeys(
            from: start,
            to: end,
            schedule: habit.schedule,
            timeZone: timeZone
        )
        let evaluations = keys.map { key in
            HabitStatisticsEngine.evaluate(
                habit: habit,
                periodKey: key,
                checkIns: checkIns,
                period: storedPeriods.first(where: { $0.periodKey == key }),
                timeZone: timeZone
            )
        }
        let stats = HabitStatisticsEngine.stats(
            habit: habit,
            periods: evaluations,
            checkIns: checkIns,
            now: Date(),
            timeZone: timeZone
        )
        return HabitWriteResult(
            habit: habit,
            stats: stats,
            effects: WriteEffects(
                sqliteCommitted: committed,
                cloudOutboxRecordNames: outboxNames,
                dryRun: dryRun
            )
        )
    }
}
