import XCTest
@testable import CalendarCountdownCore

final class DomainLinkAndTimeTests: XCTestCase {
    func testLocalDateRoundTripAndOrdering() throws {
        let date = try XCTUnwrap(LocalDate.parse("2026-09-12"))
        XCTAssertEqual(date.isoString, "2026-09-12")
        XCTAssertEqual(try JSONCoding.decoder().decode(LocalDate.self, from: Data("\"2026-09-12\"".utf8)), date)
        XCTAssertTrue(LocalDate(year: 2026, month: 2, day: 1) < date)
        XCTAssertNil(LocalDate.parse("2026-13-01"))
    }

    func testRFC3339OccurrenceKeyIsStable() {
        let seriesID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let due = RFC3339.parse("2026-09-12T07:00:00Z")!
        XCTAssertEqual(
            RecurrenceEngine.occurrenceKey(seriesID: seriesID, plannedDue: due),
            "11111111-1111-1111-1111-111111111111@2026-09-12T07:00:00Z"
        )
    }

    func testDomainLinksParseTaskOccurrenceAndHabitCheckIn() throws {
        let taskID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let key = RecurrenceEngine.occurrenceKey(
            seriesID: taskID,
            plannedDue: RFC3339.parse("2026-09-12T07:00:00Z")!
        )
        let taskURL = try XCTUnwrap(DomainLink.task(taskID, occurrenceKey: key).url)
        let parsedTask = try XCTUnwrap(DomainLink.parse(taskURL))
        XCTAssertEqual(parsedTask.kind, .task)
        XCTAssertEqual(parsedTask.id, taskID)
        XCTAssertEqual(parsedTask.occurrenceKey, key)

        let habitID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let checkInID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let habitURL = try XCTUnwrap(DomainLink.habit(habitID, checkInID: checkInID).url)
        let parsedHabit = try XCTUnwrap(DomainLink.parse(habitURL))
        XCTAssertEqual(parsedHabit.checkInID, checkInID)

        let eventURL = "calendarcountdown://event/\(taskID.uuidString)"
        XCTAssertEqual(DomainLink.parse(eventURL)?.kind, .event)
    }

    func testHybridLogicalClockOrdersConcurrentUpdates() {
        let deviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!
        let deviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var clock = HybridLogicalTimestamp.now(deviceID: deviceA, at: t0)
        clock = clock.incremented(at: t0, deviceID: deviceA)
        let remote = HybridLogicalTimestamp.now(deviceID: deviceB, at: t0).incremented(at: t0, deviceID: deviceB)
        let merged = clock.receive(remote, at: t0, deviceID: deviceA)
        XCTAssertGreaterThan(merged, clock)
        XCTAssertGreaterThan(merged, remote)
    }
}

final class RecurrenceEngineTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    func testDailyFixedScheduleRespectsCount() throws {
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .daily,
            interval: 1,
            end: .afterOccurrences(6),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let first = try date(2026, 9, 10, 15, 0, timeZone: shanghai)
        let dates = try RecurrenceEngine.dueDates(
            spec: spec,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(LocalDate.from(dates[5], timeZone: shanghai).isoString, "2026-09-15")
    }

    func testWeeklyFixedScheduleDoesNotWaitForPreviousCompletion() throws {
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .weekly,
            interval: 1,
            weekdays: [.monday, .wednesday],
            end: .afterOccurrences(6),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let first = try date(2026, 9, 7, 9, 0, timeZone: shanghai)
        let dates = try RecurrenceEngine.dueDates(
            spec: spec,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(
            dates.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2026-09-07", "2026-09-09", "2026-09-14", "2026-09-16", "2026-09-21", "2026-09-23"]
        )
    }

    func testMonthlyClampAndSkip() throws {
        let clamp = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .monthly,
            interval: 1,
            monthDays: [31],
            end: .afterOccurrences(4),
            timeZoneIdentifier: "Asia/Shanghai",
            invalidDatePolicy: .clampToMonthEnd
        ).validated()
        let first = try date(2026, 1, 31, 9, 0, timeZone: shanghai)
        let clamped = try RecurrenceEngine.dueDates(
            spec: clamp,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(
            clamped.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]
        )

        let skip = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .monthly,
            interval: 1,
            monthDays: [31],
            end: .afterOccurrences(3),
            timeZoneIdentifier: "Asia/Shanghai",
            invalidDatePolicy: .skip
        ).validated()
        let skipped = try RecurrenceEngine.dueDates(
            spec: skip,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(
            skipped.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2026-01-31", "2026-03-31", "2026-05-31"]
        )
    }

    func testLastWeekdayOfMonth() throws {
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .monthly,
            interval: 1,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            setPositions: [-1],
            end: .afterOccurrences(3),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let first = try date(2026, 9, 30, 18, 0, timeZone: shanghai)
        let dates = try RecurrenceEngine.dueDates(
            spec: spec,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(
            dates.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2026-09-30", "2026-10-30", "2026-11-30"]
        )
    }

    func testLeapDayClampAndSkip() throws {
        let first = try date(2024, 2, 29, 10, 0, timeZone: shanghai)
        let clamp = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .yearly,
            interval: 1,
            end: .afterOccurrences(3),
            timeZoneIdentifier: "Asia/Shanghai",
            invalidDatePolicy: .clampToMonthEnd
        ).validated()
        let clamped = try RecurrenceEngine.dueDates(
            spec: clamp,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(
            clamped.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2024-02-29", "2025-02-28", "2026-02-28"]
        )

        let skip = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .yearly,
            interval: 1,
            end: .afterOccurrences(2),
            timeZoneIdentifier: "Asia/Shanghai",
            invalidDatePolicy: .skip
        ).validated()
        let skipped = try RecurrenceEngine.dueDates(
            spec: skip,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(
            skipped.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2024-02-29", "2028-02-29"]
        )
    }

    func testWeeklyWallClockSurvivesDST() throws {
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .weekly,
            interval: 1,
            weekdays: [.monday],
            end: .afterOccurrences(3),
            timeZoneIdentifier: "America/Los_Angeles"
        ).validated()
        let first = try date(2026, 3, 2, 9, 0, timeZone: losAngeles)
        let dates = try RecurrenceEngine.dueDates(
            spec: spec,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "America/Los_Angeles")
        )
        XCTAssertEqual(dates.count, 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        for item in dates {
            XCTAssertEqual(calendar.component(.hour, from: item), 9)
            XCTAssertEqual(calendar.component(.weekday, from: item), Weekday.monday.rawValue)
        }
        XCTAssertEqual(LocalDate.from(dates[1], timeZone: losAngeles).isoString, "2026-03-09")
    }

    func testAfterCompletionAddsIntervalFromCompletionTime() throws {
        let spec = try RecurrenceSpec(
            mode: .afterCompletion,
            frequency: .daily,
            interval: 3,
            end: .afterOccurrences(4),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let completed = try date(2026, 9, 10, 15, 0, timeZone: shanghai)
        let next = try XCTUnwrap(
            RecurrenceEngine.nextAfterCompletion(spec: spec, completedAt: completed, previousDue: completed)
        )
        XCTAssertEqual(LocalDate.from(next, timeZone: shanghai).isoString, "2026-09-13")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        XCTAssertEqual(calendar.component(.hour, from: next), 15)
    }

    func testUntilDateIsInclusive() throws {
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .daily,
            interval: 1,
            end: .onDate(LocalDate(year: 2026, month: 9, day: 12)),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let first = try date(2026, 9, 10, 8, 0, timeZone: shanghai)
        let dates = try RecurrenceEngine.dueDates(
            spec: spec,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertEqual(
            dates.map { LocalDate.from($0, timeZone: shanghai).isoString },
            ["2026-09-10", "2026-09-11", "2026-09-12"]
        )
    }

    func testHorizonTakesTheLargerOfThirtyDaysAndTenOccurrences() throws {
        let spec = try RecurrenceSpec(
            mode: .fixedSchedule,
            frequency: .daily,
            interval: 1,
            end: .never,
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let first = try date(2026, 9, 1, 9, 0, timeZone: shanghai)
        let dates = try RecurrenceEngine.dueDates(
            spec: spec,
            firstDue: first,
            now: first,
            horizon: .default,
            calendar: try RecurrenceEngine.gregorianCalendar(timeZoneIdentifier: "Asia/Shanghai")
        )
        XCTAssertGreaterThanOrEqual(dates.count, 30)
        XCTAssertEqual(LocalDate.from(dates.last!, timeZone: shanghai).isoString, "2026-10-01")
    }

    func testRRULERoundTrip() throws {
        let spec = try RecurrenceSpec(
            mode: .afterCompletion,
            frequency: .monthly,
            interval: 3,
            weekdays: [.monday, .friday],
            setPositions: [-1],
            end: .afterOccurrences(4),
            timeZoneIdentifier: "Asia/Shanghai"
        ).validated()
        let encoded = RecurrenceRuleCodec.rrule(from: spec)
        let decoded = try RecurrenceRuleCodec.spec(from: encoded, timeZoneIdentifier: spec.timeZoneIdentifier)
        XCTAssertEqual(decoded.mode, .afterCompletion)
        XCTAssertEqual(decoded.frequency, .monthly)
        XCTAssertEqual(decoded.interval, 3)
        XCTAssertEqual(decoded.weekdays, [.monday, .friday])
        XCTAssertEqual(decoded.setPositions, [-1])
        XCTAssertEqual(decoded.end, .afterOccurrences(4))
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try XCTUnwrap(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
        )
    }
}

final class MissionProgressTests: XCTestCase {
    func testBlueprintDilutionSequence() {
        let series = UUID()
        func items(total: Int, done: Int, extraFive: Bool = false) -> [OccurrenceContribution] {
            var result: [OccurrenceContribution] = []
            for index in 0..<total {
                result.append(
                    OccurrenceContribution(
                        seriesID: series,
                        occurrenceID: UUID(),
                        title: "任务 \(index + 1)",
                        workload: .one,
                        status: index < done ? .completed : .open,
                        isFinitePlan: true,
                        includeInProgress: true
                    )
                )
            }
            if extraFive {
                result.append(
                    OccurrenceContribution(
                        seriesID: UUID(),
                        occurrenceID: UUID(),
                        title: "大型任务",
                        workload: .five,
                        status: .open,
                        isFinitePlan: true,
                        includeInProgress: true
                    )
                )
            }
            return result
        }

        let first = ProgressCalculator.breakdown(from: items(total: 10, done: 4))
        XCTAssertEqual(first.donePoints, 4)
        XCTAssertEqual(first.totalPoints, 10)
        XCTAssertEqual(first.progress, 0.4)

        let second = ProgressCalculator.breakdown(
            from: items(total: 12, done: 4),
            previous: (4, 10)
        )
        XCTAssertEqual(second.progress, 4.0 / 12.0)
        XCTAssertEqual(second.dilution?.previousTotal, 10)

        let third = ProgressCalculator.breakdown(from: items(total: 12, done: 5))
        XCTAssertEqual(third.progress, 5.0 / 12.0)

        let fourth = ProgressCalculator.breakdown(from: items(total: 12, done: 5, extraFive: true))
        XCTAssertEqual(fourth.donePoints, 5)
        XCTAssertEqual(fourth.totalPoints, 17)
        XCTAssertEqual(fourth.progress, 5.0 / 17.0)
    }

    func testUnplannedAndInfiniteAndSkip() {
        let infinite = OccurrenceContribution(
            seriesID: UUID(),
            occurrenceID: UUID(),
            title: "每周复盘",
            workload: .one,
            status: .open,
            isFinitePlan: false,
            includeInProgress: false,
            exclusionReason: "无限循环不进入成果进度分母，只计入持续性。"
        )
        let skipped = OccurrenceContribution(
            seriesID: UUID(),
            occurrenceID: UUID(),
            title: "跳过的练习",
            workload: .two,
            status: .skipped,
            isFinitePlan: true,
            includeInProgress: true
        )
        let empty = ProgressCalculator.breakdown(from: [infinite])
        XCTAssertTrue(empty.isUnplanned)
        XCTAssertNil(empty.progress)
        XCTAssertEqual(empty.excludedInfiniteSeriesCount, 1)

        let mixed = ProgressCalculator.breakdown(from: [infinite, skipped])
        XCTAssertEqual(mixed.totalPoints, 2)
        XCTAssertEqual(mixed.donePoints, 0)
        XCTAssertEqual(mixed.progress, 0)
    }
}

final class HabitStatisticsTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    func testDailyPeriodKeysAndStreakIgnoresSkip() throws {
        let habit = try HabitDefinition(
            title: "早睡",
            metric: .binary,
            schedule: .daily,
            activeFrom: LocalDate(year: 2026, month: 9, day: 1),
            modifiedByDevice: UUID()
        ).validated()
        let evaluations = [
            HabitPeriodEvaluation(periodKey: "2026-09-01", target: 1, actual: 1, isRestDay: false, isSkipped: false, isSuccess: true, isFailure: false),
            HabitPeriodEvaluation(periodKey: "2026-09-02", target: 1, actual: 0, isRestDay: false, isSkipped: true, isSuccess: false, isFailure: false),
            HabitPeriodEvaluation(periodKey: "2026-09-03", target: 1, actual: 1, isRestDay: false, isSkipped: false, isSuccess: true, isFailure: false),
            HabitPeriodEvaluation(periodKey: "2026-09-04", target: 1, actual: 1, isRestDay: false, isSkipped: false, isSuccess: true, isFailure: false)
        ]
        let streaks = HabitStatisticsEngine.streaks(from: evaluations)
        XCTAssertEqual(streaks.current, 3)
        XCTAssertEqual(streaks.longest, 3)

        let now = try date(2026, 9, 4, 22, 0)
        XCTAssertEqual(
            HabitStatisticsEngine.periodKey(for: now, schedule: habit.schedule, timeZone: shanghai),
            "2026-09-04"
        )
    }

    func testSelectedWeekdaysTreatOtherDaysAsRest() throws {
        let schedule = try HabitSchedule(kind: .selectedWeekdays, weekdays: [.monday, .wednesday]).validated()
        let monday = try date(2026, 9, 7, 8, 0)
        let tuesday = try date(2026, 9, 8, 8, 0)
        XCTAssertEqual(
            HabitStatisticsEngine.periodKey(for: monday, schedule: schedule, timeZone: shanghai),
            "2026-09-07"
        )
        XCTAssertTrue(HabitStatisticsEngine.isRestDay(date: tuesday, schedule: schedule, timeZone: shanghai))
    }

    func testQuantityRemainingAndReachTarget() throws {
        let habit = try HabitDefinition(
            title: "阅读",
            metric: .quantity,
            targetValue: 30,
            unit: "分钟",
            schedule: .daily,
            activeFrom: LocalDate(year: 2026, month: 9, day: 1),
            modifiedByDevice: UUID()
        ).validated()
        let checkIn = CheckInRecord(
            habitID: habit.id,
            periodKey: "2026-09-10",
            value: 20,
            unit: "分钟",
            effectiveAt: Date(),
            modifiedByDevice: UUID()
        )
        let evaluation = HabitStatisticsEngine.evaluate(
            habit: habit,
            periodKey: "2026-09-10",
            checkIns: [checkIn],
            period: nil,
            timeZone: shanghai
        )
        XCTAssertEqual(evaluation.actual, 20)
        XCTAssertFalse(evaluation.isSuccess)
        XCTAssertEqual(HabitStatisticsEngine.remainingToTarget(target: 30, actual: 20), 10)
    }

    func testWeeklyPeriodKeyUsesISOWeek() throws {
        let schedule = HabitSchedule(kind: .weeklyN, timesPerPeriod: 3)
        let date = try date(2026, 9, 10, 12, 0)
        XCTAssertEqual(
            HabitStatisticsEngine.periodKey(for: date, schedule: schedule, timeZone: shanghai),
            "2026-W37"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        return try XCTUnwrap(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
        )
    }
}

final class CloudMergePolicyTests: XCTestCase {
    func testDifferentFieldsMergeAutomatically() {
        let deviceA = UUID()
        let deviceB = UUID()
        let t0 = HybridLogicalTimestamp.now(deviceID: deviceA, at: Date(timeIntervalSince1970: 10))
        let t1 = t0.incremented(at: Date(timeIntervalSince1970: 11), deviceID: deviceA)
        let t2 = t0.incremented(at: Date(timeIntervalSince1970: 12), deviceID: deviceB)
        let result = CloudMergePolicy.merge(
            ancestor: [
                "title": FieldSnapshot(value: "旧标题", hlc: t0),
                "status": FieldSnapshot(value: "open", hlc: t0)
            ],
            server: [
                "title": FieldSnapshot(value: "旧标题", hlc: t0),
                "status": FieldSnapshot(value: "completed", hlc: t2)
            ],
            client: [
                "title": FieldSnapshot(value: "新标题", hlc: t1),
                "status": FieldSnapshot(value: "open", hlc: t0)
            ]
        )
        XCTAssertEqual(result.fields["title"] as? String, "新标题")
        XCTAssertEqual(result.fields["status"] as? String, "completed")
        XCTAssertFalse(result.hasUnresolvedConflict)
    }

    func testMarkdownConflictIsPreserved() {
        let device = UUID()
        let t0 = HybridLogicalTimestamp.now(deviceID: device, at: Date(timeIntervalSince1970: 1))
        let t1 = t0.incremented(at: Date(timeIntervalSince1970: 2), deviceID: device)
        let t2 = t0.incremented(at: Date(timeIntervalSince1970: 3), deviceID: UUID())
        let result = CloudMergePolicy.merge(
            ancestor: ["description_md": FieldSnapshot(value: "A", hlc: t0)],
            server: ["description_md": FieldSnapshot(value: "B", hlc: t2)],
            client: ["description_md": FieldSnapshot(value: "C", hlc: t1)]
        )
        XCTAssertTrue(result.hasUnresolvedConflict)
        if case let .conflict(local, remote, _) = result.decisions["description_md"] {
            XCTAssertEqual(local, "C")
            XCTAssertEqual(remote, "B")
        } else {
            XCTFail("expected markdown conflict")
        }
    }
}

final class ProjectionReconcilerTests: XCTestCase {
    func testLegacyCountdownEventLinkIsNotOwnedBySystemProjection() throws {
        let id = UUID()
        XCTAssertFalse(try XCTUnwrap(DomainLink.parse(DomainLink.event(id).urlString)).isSystemProjection)
        XCTAssertTrue(try XCTUnwrap(DomainLink.parse(DomainLink.task(id).urlString)).isSystemProjection)
        XCTAssertTrue(try XCTUnwrap(DomainLink.parse(DomainLink.mission(id).urlString)).isSystemProjection)
        XCTAssertTrue(try XCTUnwrap(DomainLink.parse(DomainLink.habit(id).urlString)).isSystemProjection)
    }

    func testDefaultProjectionPolicyProducesNoDesiredItems() {
        let series = TaskSeries(
            title: "写报告",
            kind: .deadline,
            schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: Date()),
            modifiedByDevice: UUID()
        )
        let occurrence = TaskOccurrence(
            seriesID: series.id,
            occurrenceKey: RecurrenceEngine.occurrenceKey(seriesID: series.id, plannedDue: Date()),
            plannedDue: Date(),
            modifiedByDevice: UUID()
        )
        let settings = ProjectionSettings.default(deviceID: UUID())
        XCTAssertFalse(settings.projectTasks)
        XCTAssertTrue(ProjectionPlanner.desired(series: series, occurrence: occurrence, settings: settings).isEmpty)
    }

    func testMissingAndNativeCompletionReverseAction() {
        let series = TaskSeries(
            title: "写报告",
            kind: .deadline,
            schedule: TaskSchedule(timeZoneIdentifier: "Asia/Shanghai", plannedDue: Date()),
            projectionPolicy: .reminder,
            modifiedByDevice: UUID()
        )
        let occurrence = TaskOccurrence(
            seriesID: series.id,
            occurrenceKey: RecurrenceEngine.occurrenceKey(seriesID: series.id, plannedDue: Date()),
            plannedDue: Date(),
            modifiedByDevice: UUID()
        )
        var settings = ProjectionSettings.default(deviceID: UUID())
        settings.projectTasks = true
        let desired = ProjectionPlanner.desired(series: series, occurrence: occurrence, settings: settings)
        XCTAssertEqual(desired.count, 1)
        XCTAssertEqual(desired[0].projectionKind, .reminder)

        let plan = ProjectionReconciler.plan(desired: desired, native: [])
        XCTAssertEqual(plan.first?.classification, .missingProjection)

        let store = InMemoryProjectionStore()
        _ = store.upsert(desired[0])
        store.complete(url: desired[0].url)
        let actions = ProjectionReconciler.reverseActions(
            desired: desired,
            native: store.items,
            acceptNativeCompletion: true
        )
        XCTAssertEqual(actions, [.complete(occurrenceID: occurrence.id)])
    }

    func testHabitAndMissionReverseActionsUseDomainType() {
        var settings = ProjectionSettings.default(deviceID: UUID())
        settings.projectHabits = true
        settings.projectMissions = true
        let habit = HabitDefinition(
            title: "阅读",
            metric: .binary,
            activeFrom: LocalDate(year: 2026, month: 9, day: 1),
            projectionPolicy: .reminder,
            modifiedByDevice: UUID()
        )
        let mission = MissionDefinition(
            title: "学会钢琴",
            modifiedByDevice: UUID()
        )
        let habitDesired = ProjectionPlanner.desired(habit: habit, settings: settings)
        let missionDesired = ProjectionPlanner.desired(mission: mission, settings: settings)
        XCTAssertEqual(habitDesired.first?.domainType, "habit")
        XCTAssertEqual(missionDesired.first?.domainType, "mission")

        let store = InMemoryProjectionStore()
        _ = store.upsert(habitDesired[0])
        store.complete(url: habitDesired[0].url)
        XCTAssertEqual(
            ProjectionReconciler.reverseActions(
                desired: habitDesired,
                native: store.items,
                acceptNativeCompletion: true
            ),
            [.checkInHabit(habitID: habit.id)]
        )

        let missionStore = InMemoryProjectionStore()
        _ = missionStore.upsert(missionDesired[0])
        missionStore.complete(url: missionDesired[0].url)
        XCTAssertEqual(
            ProjectionReconciler.reverseActions(
                desired: missionDesired,
                native: missionStore.items,
                acceptNativeCompletion: true
            ),
            [.completeMission(missionID: mission.id)]
        )
    }
}

final class DomainCommandExampleTests: XCTestCase {
    func testV2CommandExamplesDecode() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let examples = repositoryRoot.appendingPathComponent("Documentation/examples/v2", isDirectory: true)

        _ = try JSONCoding.decoder().decode(
            CreateTaskCommand.self,
            from: Data(contentsOf: examples.appendingPathComponent("task.create.example.json"))
        )
        _ = try JSONCoding.decoder().decode(
            CreateMissionCommand.self,
            from: Data(contentsOf: examples.appendingPathComponent("mission.create.example.json"))
        )
        _ = try JSONCoding.decoder().decode(
            CreateHabitCommand.self,
            from: Data(contentsOf: examples.appendingPathComponent("habit.create.example.json"))
        )
    }
}

final class AppNavigationContractTests: XCTestCase {
    func testFourPrimarySectionsNeverIncludeTodayOrMore() {
        XCTAssertEqual(AppSection.allCases.count, 4)
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), ["countdown", "tasks", "missions", "habits"])
        XCTAssertEqual(AppRoute.parse(url: URL(string: "calendarcountdown://habits")!), .section(.habits))
        XCTAssertNil(AppRoute.parse(url: URL(string: "calendarcountdown://today")!))
        XCTAssertNil(AppRoute.parse(url: URL(string: "calendarcountdown://more")!))
    }
}
