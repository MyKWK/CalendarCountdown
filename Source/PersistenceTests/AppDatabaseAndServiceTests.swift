import XCTest
@testable import CalendarCountdownCore
@testable import CalendarCountdownPersistence

final class AppDatabaseAndServiceTests: XCTestCase {
    func testOpenMigratesAndPassesIntegrity() throws {
        let db = try AppDatabase.openTemporary()
        try db.checkIntegrity()
        XCTAssertFalse(db.deviceID.uuidString.isEmpty)
        let settings = try db.read { db in
            try DomainQueries.projectionSettings(db)
        }
        XCTAssertEqual(settings?.projectTasks, false)
    }

    func testCreateCompleteAndMissionDilution() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let shanghai = "Asia/Shanghai"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: shanghai)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 9))!

        let mission = try workspace.missions.create(
            CreateMissionCommand(title: "学会钢琴曲《致爱丽丝》"),
            options: WriteOptions(now: now)
        ).mission

        func addTask(title: String, dueDay: Int) throws -> TaskOccurrence {
            let due = calendar.date(from: DateComponents(year: 2026, month: 9, day: dueDay, hour: 15))!
            let result = try workspace.tasks.create(
                CreateTaskCommand(
                    title: title,
                    missionID: mission.id,
                    schedule: TaskSchedule(timeZoneIdentifier: shanghai, plannedDue: due)
                ),
                options: WriteOptions(now: now)
            )
            return try XCTUnwrap(result.occurrences.first)
        }

        var completed: [TaskOccurrence] = []
        for day in 1...10 {
            let occurrence = try addTask(title: "练习 \(day)", dueDay: day)
            if day <= 4 {
                let done = try workspace.tasks.complete(occurrenceID: occurrence.id, options: WriteOptions(now: now))
                completed.append(contentsOf: done.occurrences.filter { $0.status == .completed })
            }
        }

        let forty = try workspace.missions.get(id: mission.id).progress
        XCTAssertEqual(forty.donePoints, 4)
        XCTAssertEqual(forty.totalPoints, 10)
        XCTAssertEqual(forty.progress, 0.4)

        _ = try addTask(title: "新增 11", dueDay: 11)
        _ = try addTask(title: "新增 12", dueDay: 12)
        let diluted = try workspace.missions.get(id: mission.id).progress
        XCTAssertEqual(diluted.donePoints, 4)
        XCTAssertEqual(diluted.totalPoints, 12)
        XCTAssertEqual(diluted.progress, 4.0 / 12.0)

        let extra = try addTask(title: "大型任务", dueDay: 20)
        _ = extra
        let afterFive = try workspace.tasks.create(
            CreateTaskCommand(
                title: "大型任务B",
                missionID: mission.id,
                workload: .five,
                schedule: TaskSchedule(
                    timeZoneIdentifier: shanghai,
                    plannedDue: calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 15))!
                )
            ),
            options: WriteOptions(now: now)
        )
        XCTAssertEqual(afterFive.series.workload, .five)
        let latest = try workspace.missions.get(id: mission.id).progress
        XCTAssertEqual(latest.totalPoints, 18)
        XCTAssertEqual(latest.donePoints, 4)
    }

    func testRevisionConflictAndIdempotency() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let key = "idem-create-1"
        let command = CreateTaskCommand(
            title: "剔牙",
            schedule: TaskSchedule(
                timeZoneIdentifier: "Asia/Shanghai",
                plannedDue: Date(timeIntervalSince1970: 1_788_912_000)
            )
        )
        let first = try workspace.tasks.create(
            command,
            options: WriteOptions(idempotencyKey: key, now: Date(timeIntervalSince1970: 1_788_912_000))
        )
        let second = try workspace.tasks.create(
            command,
            options: WriteOptions(idempotencyKey: key, now: Date(timeIntervalSince1970: 1_788_912_000))
        )
        XCTAssertEqual(first.series.id, second.series.id)

        XCTAssertThrowsError(
            try workspace.tasks.complete(
                occurrenceID: first.occurrences[0].id,
                options: WriteOptions(ifRevision: 99)
            )
        ) { error in
            let domain = error as? DomainError
            XCTAssertEqual(domain?.code, .revisionConflict)
        }
    }

    func testAfterCompletionDoesNotCreateNextUntilComplete() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let spec = try RecurrenceSpec(
            mode: .afterCompletion,
            frequency: .daily,
            interval: 3,
            end: .afterOccurrences(4),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let due = Date(timeIntervalSince1970: 1_788_912_000)
        let created = try workspace.tasks.create(
            CreateTaskCommand(
                title: "每三天",
                schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: due),
                recurrence: spec
            )
        )
        XCTAssertEqual(created.occurrences.count, 1)
        let completed = try workspace.tasks.complete(occurrenceID: created.occurrences[0].id)
        XCTAssertEqual(completed.occurrences.filter { $0.deletedAt == nil }.count, 2)
        XCTAssertEqual(completed.occurrences.filter { $0.status == .open }.count, 1)
    }

    func testTransactionRollsBackJournalAndOutboxTogether() throws {
        let db = try AppDatabase.openTemporary()
        XCTAssertThrowsError(
            try db.write { db in
                let mission = try MissionDefinition(
                    title: "回滚测试",
                    modifiedByDevice: UUID()
                ).validated()
                try MissionRow(mission).insert(db)
                try DomainWriter.enqueueOutbox(
                    db,
                    recordType: "CDMission",
                    recordName: mission.id,
                    operation: "upsert",
                    revision: 1,
                    now: Date()
                )
                throw DomainError.validation("forced-failure")
            }
        )
        let missions = try db.read { db in
            try DomainQueries.missions(db)
        }
        let outbox = try db.read { db in
            try CloudOutboxRow.fetchCount(db)
        }
        XCTAssertTrue(missions.isEmpty)
        XCTAssertEqual(outbox, 0)
    }

    func testHabitCheckInAndUndoKeepsStatsOnSQLite() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let habit = try workspace.habits.create(
            CreateHabitCommand(
                title: "阅读",
                metric: .quantity,
                targetValue: 30,
                unit: "分钟",
                activeFrom: LocalDate(year: 2026, month: 9, day: 1)
            )
        ).habit
        let first = try workspace.habits.checkIn(habitID: habit.id, value: 20)
        XCTAssertEqual(first.checkIn?.value, 20)
        XCTAssertEqual(first.stats?.totalValue, 20)
        let undone = try workspace.habits.undoCheckIn(id: first.checkIn!.id)
        XCTAssertEqual(undone.stats?.totalValue, 0)
    }

    func testCanonicalExportImportIsIdempotent() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        _ = try workspace.missions.create(CreateMissionCommand(title: "健康"))
        let snapshot = try workspace.exchange.exportSnapshot(timeZoneIdentifier: "Asia/Shanghai")
        XCTAssertEqual(snapshot.schemaVersion, 2)
        let preview = try workspace.exchange.importSnapshot(
            snapshot,
            options: WriteOptions(dryRun: true)
        )
        XCTAssertEqual(preview.dryRun, true)
        _ = try workspace.exchange.importSnapshot(snapshot)
        let again = try workspace.exchange.previewImport(snapshot)
        XCTAssertEqual(again.missionCreates, 0)
        XCTAssertEqual(try workspace.missions.list().count, 1)
    }

    func testCloudOutboxRoundTripMergesDifferentFields() throws {
        let deviceA = try Workspace(db: AppDatabase.openTemporary())
        let deviceB = try Workspace(db: AppDatabase.openTemporary())
        let created = try deviceA.missions.create(
            CreateMissionCommand(title: "学会钢琴", markdownDescription: "原说明")
        )
        let bundle = try deviceA.cloud.exportPending(ack: true)
        let applied = try deviceB.cloud.apply(bundle)
        XCTAssertEqual(applied.created, 1)
        XCTAssertEqual(try deviceB.missions.get(id: created.mission.id).mission.title, "学会钢琴")

        _ = try deviceA.missions.update(id: created.mission.id, title: "学会钢琴曲")
        _ = try deviceB.missions.update(id: created.mission.id, markdownDescription: "新说明")
        let fromA = try deviceA.cloud.exportPending(ack: true)
        let fromB = try deviceB.cloud.exportPending(ack: true)
        let intoB = try deviceB.cloud.apply(fromA)
        let intoA = try deviceA.cloud.apply(fromB)
        XCTAssertEqual(intoB.conflicts, 0)
        XCTAssertEqual(intoA.conflicts, 0)
        XCTAssertEqual(try deviceA.missions.get(id: created.mission.id).mission.title, "学会钢琴曲")
        XCTAssertEqual(try deviceB.missions.get(id: created.mission.id).mission.title, "学会钢琴曲")
        XCTAssertEqual(try deviceA.missions.get(id: created.mission.id).mission.markdownDescription, "新说明")
        XCTAssertEqual(try deviceB.missions.get(id: created.mission.id).mission.markdownDescription, "新说明")
    }

    func testDesiredProjectionsStayOffUntilEnabled() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        _ = try workspace.tasks.create(
            CreateTaskCommand(
                title: "投影任务",
                schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: Date()),
                projectionPolicy: .reminder
            )
        )
        XCTAssertTrue(try workspace.desiredProjections().isEmpty)
        try workspace.setProjectTasks(true)
        XCTAssertEqual(try workspace.desiredProjections().count, 1)
        XCTAssertEqual(try workspace.desiredProjections().first?.projectionKind, .reminder)
    }

    func testFixedScheduleMaterializesIndependentOccurrences() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .weekly,
            interval: 1,
            weekdays: [.monday, .wednesday],
            end: .afterOccurrences(6),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let firstDue = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        let created = try workspace.tasks.create(
            CreateTaskCommand(
                title: "周一三剔牙",
                schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: firstDue),
                recurrence: spec
            )
        )
        XCTAssertEqual(created.occurrences.count, 6)
        XCTAssertEqual(created.occurrences.filter { $0.status == .open }.count, 6)
    }

    func testPermanentDeleteExportsTombstoneAndAckDoesNotDropIt() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let created = try workspace.tasks.create(
            CreateTaskCommand(
                title: "会被删除",
                schedule: TaskSchedule(
                    timeZoneIdentifier: "Asia/Shanghai",
                    plannedDue: Date(timeIntervalSince1970: 1_788_912_000)
                )
            )
        )
        _ = try workspace.tasks.delete(
            seriesID: created.series.id,
            permanent: true,
            confirmID: created.series.id
        )
        let detailed = try workspace.cloud.exportPendingDetailed(ack: false)
        XCTAssertGreaterThanOrEqual(detailed.bundle.records.count, 1)
        XCTAssertTrue(detailed.bundle.records.contains { $0.operation == "delete" && $0.recordName == created.series.id })
        XCTAssertTrue(detailed.bundle.records.contains { $0.deletedAt != nil })
        XCTAssertEqual(detailed.report.skipped, 0)

        let acked = try workspace.cloud.exportPendingDetailed(ack: true)
        XCTAssertEqual(acked.report.acked, acked.bundle.records.count)
        let remaining = try workspace.cloud.status().pendingOutbox
        XCTAssertEqual(remaining, 0)

        let remote = try Workspace(db: AppDatabase.openTemporary())
        _ = try remote.cloud.apply(acked.bundle)
        XCTAssertThrowsError(try remote.tasks.get(seriesID: created.series.id))
    }

    func testPatchThisOccurrenceDoesNotRewriteSeriesTitle() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let created = try workspace.tasks.create(
            CreateTaskCommand(
                title: "系列标题",
                schedule: TaskSchedule(
                    timeZoneIdentifier: "Asia/Shanghai",
                    plannedDue: Date(timeIntervalSince1970: 1_788_912_000)
                )
            )
        )
        let occurrenceID = created.occurrences[0].id
        let patched = try workspace.tasks.patch(
            occurrenceID: occurrenceID,
            command: PatchTaskCommand(title: "仅此实例", scope: .thisOccurrence)
        )
        XCTAssertEqual(patched.series.title, "系列标题")
        XCTAssertEqual(patched.occurrences[0].titleOverride, "仅此实例")
    }

    func testProjectionCoordinatorConsumesPendingOperations() async throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        try workspace.setProjectTasks(true)
        let created = try workspace.tasks.create(
            CreateTaskCommand(
                title: "投影",
                schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: Date()),
                projectionPolicy: .reminder
            )
        )
        let store = InMemoryProjectionStore()
        let report = try await workspace.reconcileProjections(using: store)
        XCTAssertEqual(report.applied, 1)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(try workspace.cloud.pendingSagaCount(), 0)
        _ = created
    }

    func testApplicationRouterCreatesTaskThroughUnifiedCommand() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let router = ApplicationRouter(workspace: workspace)
        let command = CreateTaskCommand(
            title: "路由任务",
            schedule: TaskSchedule(
                timeZoneIdentifier: "Asia/Shanghai",
                plannedDue: Date(timeIntervalSince1970: 1_788_912_000)
            )
        )
        let params = String(decoding: try JSONCoding.encoder(pretty: false).encode(command), as: UTF8.self)
        let json = try router.dispatch(method: "tasks.create", paramsJSON: params, options: WriteOptions())
        XCTAssertTrue(json.contains("路由任务"))
        XCTAssertEqual(try workspace.tasks.list().count, 1)
    }

    func testUnknownCLIFlagIsRejected() throws {
        XCTAssertThrowsError(
            try CLIArgumentValidator.validate(
                ["capabilities", "--bogus"],
                spec: .command([], positionals: 1)
            )
        ) { error in
            XCTAssertEqual((error as? DomainError)?.code, .unknownArgument)
        }
    }

    func testValueFlagWithoutValueAndInvalidTransportAreRejected() throws {
        XCTAssertThrowsError(
            try CLIArgumentValidator.validate(
                ["export", "--output"],
                spec: .command([], values: ["--output"], positionals: 1)
            )
        ) { error in
            XCTAssertEqual((error as? DomainError)?.code, .unknownArgument)
        }
        XCTAssertThrowsError(
            try CLIArgumentValidator.validate(
                ["capabilities", "--transport", "xxx"],
                spec: .command([], positionals: 1)
            )
        ) { error in
            XCTAssertEqual((error as? DomainError)?.code, .unknownArgument)
        }
    }

    func testHabitPeriodOutboxRoundTripBetweenDatabases() throws {
        let deviceA = try Workspace(db: AppDatabase.openTemporary())
        let deviceB = try Workspace(db: AppDatabase.openTemporary())
        let habit = try deviceA.habits.create(
            CreateHabitCommand(
                title: "阅读",
                metric: .binary,
                activeFrom: LocalDate(year: 2026, month: 9, day: 1)
            )
        ).habit
        _ = try deviceB.cloud.apply(try deviceA.cloud.exportPending(ack: true))
        let skipped = try deviceA.habits.skipPeriod(habitID: habit.id, periodKey: "2026-09-10")
        XCTAssertEqual(skipped.period?.disposition, .skipped)
        XCTAssertEqual(skipped.effects.cloudOutboxRecordNames.count, 1)
        XCTAssertEqual(
            skipped.effects.cloudOutboxRecordNames.first,
            CloudRecordIdentity.habitPeriod(habitID: habit.id, periodKey: "2026-09-10").uuidString.lowercased()
        )
        let applied = try deviceB.cloud.apply(try deviceA.cloud.exportPending(ack: true))
        XCTAssertGreaterThanOrEqual(applied.applied, 1)
        let remotePeriod = try deviceB.db.read { db in
            try DomainQueries.periods(db, habitID: habit.id).first(where: { $0.periodKey == "2026-09-10" })
        }
        XCTAssertEqual(remotePeriod?.disposition, .skipped)
    }

    func testCloudInboxDefersOccurrenceUntilSeriesArrives() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let series = try workspace.tasks.create(
            CreateTaskCommand(
                title: "依赖",
                schedule: TaskSchedule(
                    timeZoneIdentifier: "Asia/Shanghai",
                    plannedDue: Date(timeIntervalSince1970: 1_788_912_000)
                )
            )
        )
        let occurrence = series.occurrences[0]
        let bundle = try workspace.cloud.exportPending(ack: true)
        let occurrenceEnvelope = try XCTUnwrap(bundle.records.first { $0.recordType == "CDTaskOccurrence" })
        let seriesEnvelope = try XCTUnwrap(bundle.records.first { $0.recordType == "CDTaskSeries" })

        let remote = try Workspace(db: AppDatabase.openTemporary())
        let deferred = try remote.cloud.ingestFetched([occurrenceEnvelope])
        XCTAssertEqual(deferred.skipped, 1)
        XCTAssertEqual(deferred.failed, 0)
        XCTAssertTrue(deferred.lastFetchAdvanced)
        XCTAssertEqual(try remote.cloud.inboxCount(), 1)
        XCTAssertThrowsError(try remote.tasks.get(seriesID: series.series.id))

        let replayed = try remote.cloud.ingestFetched([seriesEnvelope])
        XCTAssertGreaterThanOrEqual(replayed.applied, 2)
        XCTAssertEqual(try remote.cloud.inboxCount(), 0)
        XCTAssertEqual(try remote.tasks.get(seriesID: series.series.id).occurrences.count, 1)
        _ = occurrence
    }

    func testCloudInboxKeepsBadPayloadAndDoesNotAdvanceFetch() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let bad = CloudRecordEnvelope(
            recordType: "CDTaskOccurrence",
            recordName: UUID(),
            operation: "upsert",
            revision: 1,
            payloadJSON: "{not-json",
            modifiedByDevice: UUID(),
            updatedAt: Date()
        )
        let report = try workspace.cloud.ingestFetched([bad])
        XCTAssertEqual(report.failed, 1)
        XCTAssertFalse(report.lastFetchAdvanced)
        XCTAssertEqual(try workspace.cloud.inboxCount(), 1)
        XCTAssertNil(try workspace.cloud.status().lastFetchAt)
    }

    func testCloudProfileIsolationDoesNotMixAccounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cc-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = CloudProfileRegistry(rootURL: root)
        let unsigned = try AppDatabase.open(
            at: registry.unsignedDatabaseURL,
            backupDirectory: registry.backupDirectoryURL
        )
        let session = CloudProfileSession(workspace: Workspace(db: unsigned), registry: registry)
        _ = try session.workspace.missions.create(CreateMissionCommand(title: "A 的使命"))
        let switchedA = try session.activateAccount(hash: "aaa111aaa111aaaa")
        XCTAssertTrue(switchedA.didChangeDatabase)
        XCTAssertEqual(try session.workspace.missions.list().count, 1)

        let signedOut = try session.lockCurrentAccount()
        XCTAssertNil(signedOut.activeAccountHash)
        XCTAssertEqual(try session.workspace.missions.list().count, 0)

        let switchedB = try session.activateAccount(hash: "bbb222bbb222bbbb")
        XCTAssertTrue(switchedB.didChangeDatabase)
        XCTAssertEqual(try session.workspace.missions.list().count, 0)
        _ = try session.workspace.missions.create(CreateMissionCommand(title: "B 的使命"))
        XCTAssertEqual(try session.workspace.missions.list().first?.mission.title, "B 的使命")

        _ = try session.lockCurrentAccount()
        _ = try session.activateAccount(hash: "aaa111aaa111aaaa")
        XCTAssertEqual(try session.workspace.missions.list().first?.mission.title, "A 的使命")
        XCTAssertTrue(try registry.isLocked("bbb222bbb222bbbb"))
    }

    func testProjectionFailureKeepsPendingSaga() async throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        try workspace.setProjectTasks(true)
        _ = try workspace.tasks.create(
            CreateTaskCommand(
                title: "投影失败",
                schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: Date()),
                projectionPolicy: .reminder
            )
        )
        let report = try await workspace.reconcileProjections(using: FailingProjectionApplier())
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.pendingCompleted, 0)
        XCTAssertEqual(try workspace.cloud.pendingSagaCount(), 1)
    }

    func testHabitAppleCompletionDispatchesCheckIn() async throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        try workspace.setProjectionSettings(projectHabits: true)
        let habit = try workspace.habits.create(
            CreateHabitCommand(
                title: "阅读",
                metric: .binary,
                activeFrom: LocalDate.from(Date(), timeZone: .current),
                projectionPolicy: .reminder
            )
        ).habit
        let desired = try workspace.desiredProjections()
        XCTAssertEqual(desired.first?.domainType, "habit")
        let store = InMemoryProjectionStore()
        _ = store.upsert(desired[0])
        store.complete(url: desired[0].url)
        let report = try await workspace.reconcileProjections(using: store)
        XCTAssertGreaterThanOrEqual(report.reverseActions, 1)
        let stats = try workspace.habits.get(id: habit.id).stats
        XCTAssertGreaterThan(stats?.totalValue ?? 0, 0)
    }

    func testMissionProjectionCanBeEnabledSeparately() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        _ = try workspace.missions.create(CreateMissionCommand(title: "学会钢琴"))
        XCTAssertTrue(try workspace.desiredProjections().isEmpty)
        _ = try workspace.setProjectionSettings(projectMissions: true)
        XCTAssertEqual(try workspace.desiredProjections().first?.domainType, "mission")
    }

    func testApplicationRouterReportsBrokerWhenConfigured() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let router = ApplicationRouter(workspace: workspace, brokerListening: true)
        let json = try router.dispatch(method: "system.capabilities", paramsJSON: "{}", options: WriteOptions())
        XCTAssertTrue(json.contains("\"broker\":true"))
        let doctor = try router.dispatch(method: "system.doctor", paramsJSON: "{}", options: WriteOptions())
        XCTAssertTrue(doctor.contains("\"brokerListening\":true"))
    }

    func testProcessWideDatabasePoolReusesTheSameConnection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cc-pool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("calendarcountdown-v2.sqlite")
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        let first = try AppDatabase.open(at: url, backupDirectory: backups)
        let second = try AppDatabase.open(at: url, backupDirectory: backups)
        XCTAssertEqual(ObjectIdentifier(first.pool), ObjectIdentifier(second.pool))
        _ = try Workspace(db: first).missions.create(CreateMissionCommand(title: "共享连接"))
        XCTAssertEqual(try Workspace(db: second).missions.list().count, 1)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testCountdownSelectionsRoundTripThroughCloudKitOutbox() throws {
        let deviceA = try Workspace(db: AppDatabase.openTemporary())
        let deviceB = try Workspace(db: AppDatabase.openTemporary())
        let draft = try ManagedEventDraft(
            title: "农历生日",
            calendarTitle: "生日",
            calendarIdentifier: "local-calendar",
            calendarSystem: .lunar,
            recurrence: .yearly,
            lunarMonth: 8,
            lunarDay: 15
        ).validated()
        let created = try deviceA.countdown.upsertManagedEvent(draft, now: Date())
        XCTAssertNotNil(created.record.draft.calendarIdentifier)
        var selection = CountdownSelection(
            mode: .managedRecord,
            calendarIdentifier: "local-calendar",
            calendarTitle: "生日",
            managedRecordID: created.record.id,
            eventTitle: "农历生日"
        )
        try deviceA.countdown.upsertSelection(selection)
        try deviceA.countdown.savePreferences(
            CountdownDisplayPreferences(pinnedSelectionID: selection.id)
        )

        let applied = try deviceB.cloud.apply(try deviceA.cloud.exportPending(ack: true))
        XCTAssertGreaterThanOrEqual(applied.created, 2)
        let remoteEvent = try XCTUnwrap(try deviceB.countdown.managedEvent(id: created.record.id))
        XCTAssertEqual(remoteEvent.draft.title, "农历生日")
        XCTAssertNil(remoteEvent.draft.calendarIdentifier)
        let remoteSelections = try deviceB.countdown.loadSelections()
        XCTAssertEqual(remoteSelections.first?.managedRecordID, created.record.id)
        XCTAssertNil(remoteSelections.first?.calendarIdentifier)
        XCTAssertEqual(try deviceB.countdown.loadPreferences().pinnedSelectionID, selection.id)
        _ = selection
    }

    func testCloudKitEngineFactoryRejectsMissingProfileSession() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        XCTAssertThrowsError(
            try CloudKitEngineFactory.make(
                workspace: workspace,
                profileSession: Optional<CloudProfileSession>.none
            )
        ) { error in
            XCTAssertEqual((error as? DomainError)?.code, .icloudUnavailable)
        }
    }

    func testBrokerStyleFirstICloudEnableIsolatesAccounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cc-broker-icloud-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = CloudProfileRegistry(rootURL: root)
        let unsigned = try AppDatabase.open(
            at: registry.unsignedDatabaseURL,
            backupDirectory: registry.backupDirectoryURL
        )
        let session = CloudProfileSession(workspace: Workspace(db: unsigned), registry: registry)
        _ = try session.workspace.missions.create(CreateMissionCommand(title: "未登录使命"))

        XCTAssertThrowsError(
            try CloudKitEngineFactory.make(
                workspace: session.workspace,
                profileSession: Optional<CloudProfileSession>.none
            )
        )

        let engine = try CloudKitEngineFactory.make(
            workspace: session.workspace,
            profileSession: session,
            automaticallySync: false,
            transport: FakeCloudSyncTransport()
        )
        XCTAssertTrue(engine.profileSession === session)

        let switchedA = try session.activateAccount(hash: "aaa111aaa111aaaa")
        XCTAssertTrue(switchedA.didChangeDatabase)
        XCTAssertEqual(try session.workspace.missions.list().first?.mission.title, "未登录使命")

        _ = try session.lockCurrentAccount()
        XCTAssertEqual(try session.workspace.missions.list().count, 0)
        _ = try session.activateAccount(hash: "bbb222bbb222bbbb")
        _ = try session.workspace.missions.create(CreateMissionCommand(title: "B 的使命"))

        _ = try session.lockCurrentAccount()
        _ = try session.activateAccount(hash: "aaa111aaa111aaaa")
        XCTAssertEqual(try session.workspace.missions.list().first?.mission.title, "未登录使命")
        XCTAssertTrue(try registry.isLocked("bbb222bbb222bbbb"))
    }

    func testSyncNowDoesNotAdvanceLastFetchWhenFetchedApplyFails() async throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        try workspace.cloud.setMode(.iCloud)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cc-fetch-fail-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = CloudProfileSession(
            workspace: workspace,
            registry: CloudProfileRegistry(rootURL: root)
        )
        let transport = FakeCloudSyncTransport()
        let engine = CloudKitEngineFactory.make(
            workspace: workspace,
            profileSession: session,
            automaticallySync: false,
            transport: transport
        )
        transport.fetchHandler = { [weak engine] in
            let bad = CloudRecordEnvelope(
                recordType: "CDTaskOccurrence",
                recordName: UUID(),
                operation: "upsert",
                revision: 1,
                payloadJSON: "{not-json",
                modifiedByDevice: UUID(),
                updatedAt: Date()
            )
            engine?.applyFetchedForTesting(envelopes: [bad])
        }

        let status = try await engine.syncNow()
        XCTAssertNil(status.lastFetchAt)
        XCTAssertEqual(try workspace.cloud.inboxCount(), 1)
        XCTAssertEqual(transport.fetchCount, 1)
    }

    func testSyncNowAdvancesLastFetchWhenFetchedApplySucceeds() async throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        try workspace.cloud.setMode(.iCloud)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cc-fetch-ok-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = CloudProfileSession(
            workspace: workspace,
            registry: CloudProfileRegistry(rootURL: root)
        )
        let transport = FakeCloudSyncTransport()
        let engine = CloudKitEngineFactory.make(
            workspace: workspace,
            profileSession: session,
            automaticallySync: false,
            transport: transport
        )
        transport.fetchHandler = { [weak engine] in
            engine?.applyFetchedForTesting(envelopes: [], decodeFailed: 0)
        }

        let status = try await engine.syncNow()
        XCTAssertNotNil(status.lastFetchAt)
        XCTAssertEqual(try workspace.cloud.inboxCount(), 0)
    }

    func testIngestFetchedCanKeepCursorWhenDecodeBatchIsPartial() throws {
        let workspace = try Workspace(db: AppDatabase.openTemporary())
        let series = try workspace.tasks.create(
            CreateTaskCommand(
                title: "保留 cursor",
                schedule: TaskSchedule(
                    timeZoneIdentifier: "Asia/Shanghai",
                    plannedDue: Date(timeIntervalSince1970: 1_788_912_000)
                )
            )
        )
        let bundle = try workspace.cloud.exportPending(ack: true)
        let seriesEnvelope = try XCTUnwrap(bundle.records.first { $0.recordType == "CDTaskSeries" })
        let remote = try Workspace(db: AppDatabase.openTemporary())
        let report = try remote.cloud.ingestFetched([seriesEnvelope], advanceFetchCursor: false)
        XCTAssertGreaterThanOrEqual(report.applied, 1)
        XCTAssertFalse(report.lastFetchAdvanced)
        XCTAssertNil(try remote.cloud.status().lastFetchAt)
        _ = series
    }
}

private struct FailingProjectionApplier: ProjectionApplying {
    func nativeItems() async throws -> [ProjectedNativeItem] { [] }

    func apply(_ desired: DesiredProjection) async throws -> String {
        throw DomainError(code: .projectionFailed, message: "forced-apply-failure")
    }

    func remove(url: String, kind: ProjectionKind) async throws {
        throw DomainError(code: .projectionFailed, message: "forced-remove-failure")
    }
}
