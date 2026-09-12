import CalendarCountdownCore
import Foundation
import GRDB

public struct ExportImportService: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func exportSnapshot(timeZoneIdentifier: String = TimeZone.current.identifier) throws -> CanonicalSnapshot {
        try db.read { db in
            try DomainQueries.snapshot(db, timeZoneIdentifier: timeZoneIdentifier)
        }
    }

    public func previewImport(_ snapshot: CanonicalSnapshot) throws -> ImportPreview {
        try db.read { db in
            try plan(snapshot, db: db)
        }
    }

    public func importSnapshot(
        _ snapshot: CanonicalSnapshot,
        options: WriteOptions = WriteOptions()
    ) throws -> ImportPreview {
        guard snapshot.schemaVersion == 2 else {
            throw DomainError.validation("不支持 schemaVersion \(snapshot.schemaVersion)，任务包仅支持 2。")
        }
        if options.dryRun {
            return try previewImport(snapshot)
        }
        return try db.write { db in
            let preview = try plan(snapshot, db: db)
            for mission in snapshot.missions {
                try MissionRow(try mission.validated()).save(db)
                try DomainWriter.enqueueOutbox(
                    db,
                    recordType: "CDMission",
                    recordName: mission.id,
                    operation: "upsert",
                    revision: mission.revision,
                    now: options.now
                )
            }
            for series in snapshot.taskSeries {
                try TaskSeriesRow(try series.validated()).save(db)
                try DomainWriter.enqueueOutbox(
                    db,
                    recordType: "CDTaskSeries",
                    recordName: series.id,
                    operation: "upsert",
                    revision: series.revision,
                    now: options.now
                )
            }
            for occurrence in snapshot.occurrences {
                try TaskOccurrenceRow(occurrence).save(db)
                try DomainWriter.enqueueOutbox(
                    db,
                    recordType: "CDTaskOccurrence",
                    recordName: occurrence.id,
                    operation: "upsert",
                    revision: occurrence.revision,
                    now: options.now
                )
            }
            for habit in snapshot.habits {
                try HabitRow(try habit.validated()).save(db)
                try DomainWriter.enqueueOutbox(
                    db,
                    recordType: "CDHabit",
                    recordName: habit.id,
                    operation: "upsert",
                    revision: habit.revision,
                    now: options.now
                )
            }
            for period in snapshot.habitPeriods {
                try HabitPeriodRow(period).save(db)
                try DomainWriter.enqueueEncoded(
                    db,
                    recordType: "CDHabitPeriod",
                    recordName: CloudRecordIdentity.habitPeriod(habitID: period.habitID, periodKey: period.periodKey),
                    operation: "upsert",
                    revision: period.revision,
                    payload: period,
                    modifiedByDevice: period.modifiedByDevice,
                    updatedAt: period.updatedAt,
                    deletedAt: period.deletedAt,
                    now: options.now
                )
            }
            for checkIn in snapshot.checkIns {
                try CheckInRow(checkIn).save(db)
                try DomainWriter.enqueueOutbox(
                    db,
                    recordType: "CDCheckIn",
                    recordName: checkIn.id,
                    operation: "upsert",
                    revision: checkIn.revision,
                    now: options.now
                )
            }
            try DomainWriter.journal(
                db,
                options: options,
                command: "import",
                objectType: "snapshot",
                objectID: UUID(),
                before: nil,
                after: 1,
                summary: "imported schema 2"
            )
            return ImportPreview(
                dryRun: false,
                missionCreates: preview.missionCreates,
                missionUpdates: preview.missionUpdates,
                taskCreates: preview.taskCreates,
                habitCreates: preview.habitCreates,
                checkInCreates: preview.checkInCreates,
                conflicts: preview.conflicts
            )
        }
    }

    private func plan(_ snapshot: CanonicalSnapshot, db: Database) throws -> ImportPreview {
        var conflicts: [String] = []
        var missionCreates = 0
        var missionUpdates = 0
        for mission in snapshot.missions {
            if let existing = try DomainQueries.mission(db, id: mission.id) {
                missionUpdates += 1
                if existing.revision > mission.revision {
                    conflicts.append("mission \(mission.id.uuidString.lowercased()) remote revision older")
                }
            } else {
                missionCreates += 1
            }
        }
        var taskCreates = 0
        for series in snapshot.taskSeries {
            if try DomainQueries.series(db, id: series.id) == nil {
                taskCreates += 1
            }
        }
        var habitCreates = 0
        for habit in snapshot.habits {
            if try DomainQueries.habit(db, id: habit.id) == nil {
                habitCreates += 1
            }
        }
        var checkInCreates = 0
        for checkIn in snapshot.checkIns {
            if try DomainQueries.checkIn(db, id: checkIn.id) == nil {
                checkInCreates += 1
            }
        }
        return ImportPreview(
            dryRun: true,
            missionCreates: missionCreates,
            missionUpdates: missionUpdates,
            taskCreates: taskCreates,
            habitCreates: habitCreates,
            checkInCreates: checkInCreates,
            conflicts: conflicts
        )
    }
}

public struct Workspace: Sendable {
    public let db: AppDatabase
    public let tasks: TaskService
    public let missions: MissionService
    public let habits: HabitService
    public let countdown: CountdownService
    public let exchange: ExportImportService
    public let cloud: CloudSyncService
    public let projections: ProjectionCoordinator

    public init(db: AppDatabase, countdown: CountdownService? = nil) {
        self.db = db
        self.countdown = countdown ?? CountdownService(db: db)
        if let countdown {
            countdown.attach(db: db)
        }
        tasks = TaskService(db: db)
        missions = MissionService(db: db)
        habits = HabitService(db: db)
        exchange = ExportImportService(db: db)
        cloud = CloudSyncService(db: db)
        projections = ProjectionCoordinator(db: db, tasks: tasks, habits: habits, missions: missions)
    }

    public static func shared() throws -> Workspace {
        let workspace = Workspace(db: try AppDatabase.openSharedContainer())
        workspace.countdown.mirrorsLegacyJSON = true
        return workspace
    }

    public func capabilities(
        remindersAccess: String? = nil,
        eventsAccess: String? = nil,
        broker: Bool = false
    ) throws -> CapabilitiesReport {
        let status = try cloud.status()
        return CapabilitiesReport(
            cloudKitMode: status.mode.rawValue,
            cloudKitAccount: status.account.rawValue,
            broker: broker,
            remindersAccess: remindersAccess,
            eventsAccess: eventsAccess
        )
    }

    public func doctor(
        remindersAccess: String = "unknown",
        eventsAccess: String = "unknown",
        brokerListening: Bool = false,
        projectionDrift: Int = 0
    ) throws -> SystemDoctorReport {
        var integrity = "ok"
        var sqliteError: String?
        do {
            try db.checkIntegrity()
        } catch {
            integrity = "error"
            sqliteError = error.localizedDescription
        }
        let status = try cloud.status()
        return SystemDoctorReport(
            sqlitePath: db.path,
            sqliteIntegrity: integrity,
            sqliteError: sqliteError,
            cloudMode: status.mode.rawValue,
            cloudKitAccount: status.account.rawValue,
            cloudOutbox: status.pendingOutbox,
            lastFetchAt: status.lastFetchAt,
            lastSendAt: status.lastSendAt,
            openConflicts: status.openConflicts,
            pendingSaga: try cloud.pendingSagaCount(),
            cloudInbox: status.pendingInbox,
            remindersAccess: remindersAccess,
            eventsAccess: eventsAccess,
            projectionDrift: projectionDrift,
            brokerListening: brokerListening
        )
    }

    public func projectionSettings() throws -> ProjectionSettings {
        let deviceID = db.deviceID
        return try db.read { db in
            try DomainQueries.projectionSettings(db) ?? .default(deviceID: deviceID)
        }
    }

    public func setProjectionSettings(
        projectTasks: Bool? = nil,
        projectHabits: Bool? = nil,
        projectMissions: Bool? = nil,
        acceptNativeCompletion: Bool? = nil,
        now: Date = Date()
    ) throws -> ProjectionSettings {
        let deviceID = db.deviceID
        return try db.write { db in
            var settings = try DomainQueries.projectionSettings(db) ?? .default(deviceID: deviceID, now: now)
            if let projectTasks { settings.projectTasks = projectTasks }
            if let projectHabits { settings.projectHabits = projectHabits }
            if let projectMissions { settings.projectMissions = projectMissions }
            if let acceptNativeCompletion { settings.acceptNativeCompletion = acceptNativeCompletion }
            settings.updatedAt = now
            settings.revision += 1
            settings.modifiedByDevice = deviceID
            try ProjectionSettingsRow(settings).save(db)
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDProjectionSettings",
                recordName: settings.id,
                operation: "upsert",
                revision: settings.revision,
                payload: settings,
                modifiedByDevice: deviceID,
                updatedAt: settings.updatedAt,
                now: now
            )
            return settings
        }
    }

    public func setProjectTasks(_ enabled: Bool, now: Date = Date()) throws {
        _ = try setProjectionSettings(projectTasks: enabled, now: now)
    }

    public func desiredProjections() throws -> [DesiredProjection] {
        try projections.desiredProjections()
    }

    public func reconcileProjections(
        using applier: any ProjectionApplying,
        dryRun: Bool = false
    ) async throws -> ProjectionReconcileReport {
        try await projections.reconcile(using: applier, dryRun: dryRun)
    }

    public func widgetSnapshotV2(countdown: [CountdownEvent] = []) throws -> WidgetSnapshotV2 {
        let openTasks = try tasks.list(TaskListFilter(openOnly: true, limit: 20))
        let missionResults = try missions.list()
        let habitResults = try habits.list()
        return WidgetSnapshotV2(
            tasks: openTasks.prefix(8).map {
                WidgetTaskItem(
                    id: $0.id,
                    title: $0.title,
                    due: $0.occurrence.plannedDue,
                    isOverdue: $0.isOverdue
                )
            },
            missions: missionResults.prefix(4).map {
                WidgetMissionItem(
                    id: $0.mission.id,
                    title: $0.mission.title,
                    progress: $0.progress.progress,
                    icon: $0.mission.icon,
                    color: $0.mission.color
                )
            },
            habits: habitResults.prefix(8).map {
                WidgetHabitItem(
                    id: $0.habit.id,
                    title: $0.habit.title,
                    currentStreak: $0.stats?.currentStreak ?? 0
                )
            },
            countdown: countdown.prefix(5).map(WidgetSnapshotItem.init(event:))
        )
    }
}
