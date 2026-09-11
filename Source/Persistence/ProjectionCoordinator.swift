import CalendarCountdownCore
import Foundation
import GRDB

public struct ProjectionCoordinator: Sendable {
    public let db: AppDatabase
    public let tasks: TaskService
    public let habits: HabitService
    public let missions: MissionService

    public init(db: AppDatabase, tasks: TaskService, habits: HabitService, missions: MissionService) {
        self.db = db
        self.tasks = tasks
        self.habits = habits
        self.missions = missions
    }

    public func reconcile(
        using applier: any ProjectionApplying,
        dryRun: Bool = false,
        now: Date = Date()
    ) async throws -> ProjectionReconcileReport {
        let deviceID = db.deviceID
        let settings = try db.read { db in
            try DomainQueries.projectionSettings(db) ?? .default(deviceID: deviceID)
        }
        let desired = try desiredProjections(settings: settings)
        let native = try await applier.nativeItems()
        let reverse = ProjectionReconciler.reverseActions(
            desired: desired,
            native: native,
            acceptNativeCompletion: settings.acceptNativeCompletion
        )
        var report = ProjectionReconcileReport(desired: desired.count, dryRun: dryRun)
        if !dryRun {
            for action in reverse {
                do {
                    try applyReverse(action, now: now)
                    report.reverseActions += 1
                } catch {
                    report.errors.append(error.localizedDescription)
                }
            }
        } else {
            report.reverseActions = reverse.count
        }

        let refreshed = try desiredProjections(settings: settings)
        let plan = ProjectionReconciler.plan(desired: refreshed, native: native)
        report.missing = plan.filter { $0.classification == .missingProjection }.count
        report.drifted = plan.filter { $0.classification == .projectionDrift }.count

        if !dryRun {
            var succeeded = Set<UUID>()
            var failed = Set<UUID>()
            for item in plan {
                do {
                    let identifier = try await applier.apply(item.desired)
                    try saveBinding(item.desired, appleIdentifier: identifier, state: .synced, now: now)
                    report.applied += 1
                    succeeded.insert(item.desired.domainID)
                } catch {
                    report.failed += 1
                    failed.insert(item.desired.domainID)
                    report.errors.append(error.localizedDescription)
                    try? saveBinding(item.desired, appleIdentifier: item.existing?.appleIdentifier, state: .failed, now: now, error: error)
                }
            }

            let desiredURLs = Set(refreshed.map { "\($0.projectionKind.rawValue)|\($0.url)" })
            for nativeItem in native {
                let key = "\(nativeItem.kind.rawValue)|\(nativeItem.url)"
                if !desiredURLs.contains(key),
                   let link = DomainLink.parse(nativeItem.url),
                   link.isSystemProjection {
                    do {
                        try await applier.remove(url: nativeItem.url, kind: nativeItem.kind)
                    } catch {
                        report.failed += 1
                        report.errors.append(error.localizedDescription)
                        if let link = DomainLink.parse(nativeItem.url) {
                            failed.insert(link.id)
                        }
                    }
                }
            }

            report.pendingCompleted = try settlePending(
                succeeded: succeeded.subtracting(failed),
                failed: failed,
                now: now
            )
        }
        return report
    }

    public func desiredProjections(settings: ProjectionSettings? = nil) throws -> [DesiredProjection] {
        let deviceID = db.deviceID
        return try db.read { db in
            let settings = try settings ?? DomainQueries.projectionSettings(db) ?? .default(deviceID: deviceID)
            var desired: [DesiredProjection] = []
            for series in try DomainQueries.seriesList(db) {
                for occurrence in try DomainQueries.occurrences(forSeries: db, seriesID: series.id) {
                    desired.append(contentsOf: ProjectionPlanner.desired(
                        series: series,
                        occurrence: occurrence,
                        settings: settings
                    ))
                }
            }
            let timeZone = TimeZone.current
            let todayKeyPrefix = LocalDate.from(Date(), timeZone: timeZone).isoString
            for habit in try DomainQueries.habits(db) {
                let periods = try DomainQueries.periods(db, habitID: habit.id)
                let periodKey = HabitStatisticsEngine.periodKey(
                    for: Date(),
                    schedule: habit.schedule,
                    timeZone: timeZone
                )
                let period = periods.first(where: { $0.periodKey == periodKey })
                    ?? periods.first(where: { $0.periodKey == todayKeyPrefix })
                desired.append(contentsOf: ProjectionPlanner.desired(habit: habit, settings: settings, period: period))
            }
            for mission in try DomainQueries.missions(db) {
                desired.append(contentsOf: ProjectionPlanner.desired(mission: mission, settings: settings))
            }
            return desired
        }
    }

    private func applyReverse(_ action: NativeReverseAction, now: Date) throws {
        let options = WriteOptions(actor: .appleCompletion, now: now)
        switch action {
        case let .complete(occurrenceID):
            _ = try tasks.complete(occurrenceID: occurrenceID, options: options)
        case let .reopen(occurrenceID):
            _ = try tasks.reopen(occurrenceID: occurrenceID, options: options)
        case let .checkInHabit(habitID):
            let habit = try habits.get(id: habitID).habit
            if let key = HabitStatisticsEngine.periodKey(for: now, schedule: habit.schedule, timeZone: .current) {
                let period = try db.read { db in
                    try DomainQueries.periods(db, habitID: habitID).first(where: { $0.periodKey == key })
                }
                if period?.disposition == .completed { return }
            }
            _ = try habits.checkIn(
                habitID: habitID,
                fillToTarget: true,
                source: .appleCompletion,
                options: options
            )
        case let .undoHabitCheckIn(habitID):
            let habit = try habits.get(id: habitID).habit
            let key = HabitStatisticsEngine.periodKey(for: now, schedule: habit.schedule, timeZone: .current)
            let checkIns = try db.read { db in
                try DomainQueries.checkIns(db, habitID: habitID)
            }
            guard let latest = checkIns
                .filter({ $0.deletedAt == nil && (key == nil || $0.periodKey == key) })
                .max(by: { $0.recordedAt < $1.recordedAt })
            else {
                return
            }
            _ = try habits.undoCheckIn(id: latest.id, options: options)
        case let .completeMission(missionID):
            _ = try missions.complete(id: missionID, options: options)
        case let .reopenMission(missionID):
            _ = try missions.setStatus(id: missionID, status: .active, options: options)
        }
    }

    private func saveBinding(
        _ desired: DesiredProjection,
        appleIdentifier: String?,
        state: ProjectionBindingState,
        now: Date,
        error: Error? = nil
    ) throws {
        try db.write { db in
            let row = ProjectionBindingRow(
                domainType: desired.domainType,
                domainId: SQLValue.uuid(desired.domainID),
                projectionKind: desired.projectionKind.rawValue,
                appleIdentifier: appleIdentifier,
                appleExternalIdentifier: nil,
                desiredRevision: desired.revision,
                projectedRevision: state == .synced ? desired.revision : nil,
                fingerprint: desired.url,
                lastSeenAt: RFC3339.utcString(from: now),
                state: state.rawValue,
                errorCode: (error as? DomainError)?.code.rawValue
            )
            try row.save(db)
        }
    }

    private func settlePending(succeeded: Set<UUID>, failed: Set<UUID>, now: Date) throws -> Int {
        try db.write { db in
            let pending = try DomainWriter.pendingOperations(db)
            var completed = 0
            for row in pending {
                let related = try relatedProjectionIDs(db, row: row)
                if related.contains(where: { failed.contains($0) }) {
                    try DomainWriter.failPending(
                        db,
                        requestID: try SQLValue.uuid(row.requestId),
                        code: "projection_failed",
                        now: now
                    )
                    continue
                }
                let objectID = try SQLValue.uuid(row.objectId)
                let stillNeeded = try stillNeedsProjection(db, objectType: row.objectType, objectID: objectID)
                if related.contains(where: { succeeded.contains($0) }) || !stillNeeded {
                    try DomainWriter.completePending(db, requestID: try SQLValue.uuid(row.requestId), now: now)
                    completed += 1
                }
            }
            return completed
        }
    }

    private func relatedProjectionIDs(_ db: Database, row: PendingOperationRow) throws -> Set<UUID> {
        let objectID = try SQLValue.uuid(row.objectId)
        var ids: Set<UUID> = [objectID]
        if row.objectType == "task_series" {
            for occurrence in try DomainQueries.occurrences(forSeries: db, seriesID: objectID) {
                ids.insert(occurrence.id)
            }
        }
        return ids
    }

    private func stillNeedsProjection(_ db: Database, objectType: String, objectID: UUID) throws -> Bool {
        let settings = try DomainQueries.projectionSettings(db) ?? .default(deviceID: self.db.deviceID)
        switch objectType {
        case "habit":
            guard let habit = try DomainQueries.habit(db, id: objectID), habit.deletedAt == nil else { return false }
            return !ProjectionPlanner.desired(habit: habit, settings: settings).isEmpty
        case "mission":
            guard let mission = try DomainQueries.mission(db, id: objectID), mission.deletedAt == nil else { return false }
            return !ProjectionPlanner.desired(mission: mission, settings: settings).isEmpty
        default:
            guard let series = try DomainQueries.series(db, id: objectID) ?? occurrenceSeries(db, objectID: objectID) else {
                return false
            }
            let occurrences = try DomainQueries.occurrences(forSeries: db, seriesID: series.id)
            return occurrences.contains { !ProjectionPlanner.desired(series: series, occurrence: $0, settings: settings).isEmpty }
        }
    }

    private func occurrenceSeries(_ db: Database, objectID: UUID) throws -> TaskSeries? {
        guard let occurrence = try DomainQueries.occurrence(db, id: objectID) else { return nil }
        return try DomainQueries.series(db, id: occurrence.seriesID)
    }
}
