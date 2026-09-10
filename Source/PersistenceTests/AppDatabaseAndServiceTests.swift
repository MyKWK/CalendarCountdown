import XCTest
import CalendarCountdownCore
#if canImport(CalendarCountdownPersistence)
@testable import CalendarCountdownPersistence
#endif

final class AppDatabaseAndServiceTests: XCTestCase {
    func testProcessWideDatabasePoolReusesTheSameConnection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-pool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("calendarcountdown-v2.sqlite")
        let first = try AppDatabase.open(at: url, backupDirectory: directory.appendingPathComponent("Backups"))
        let second = try AppDatabase.open(at: url, backupDirectory: directory.appendingPathComponent("Backups"))
        XCTAssertTrue(first.connection === second.connection)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        try first.close()
    }

    func testFetchOutcomeDoesNotAdvanceLastFetchAtOnFailure() throws {
        let database = try AppDatabase.openTemporary()
        XCTAssertNil(try database.lastFetchAt())
        try database.recordFetchOutcome(.failed)
        XCTAssertNil(try database.lastFetchAt())
        try database.recordFetchOutcome(.empty)
        XCTAssertNotNil(try database.lastFetchAt())
        try database.close()
    }

    func testCountdownSelectionsRoundTripThroughCloudKitOutbox() throws {
        let database = try AppDatabase.openTemporary()
        let store = CountdownStore(db: database)
        var selection = CountdownSelection(
            mode: .annualTitle,
            calendarTitle: "节日",
            eventTitle: "元旦",
            modifiedByDevice: database.deviceID
        )
        selection.revision = 1
        try store.persistSelection(selection)
        let outbox = try store.pendingOutbox()
        XCTAssertEqual(outbox.first?.recordType, "CDCountdownSelection")
        XCTAssertFalse(outbox.first?.payloadJSON.contains("eventIdentifier") ?? true)
        XCTAssertFalse(outbox.first?.payloadJSON.contains("calendarIdentifier") ?? true)
        try database.close()
    }

    func testManagedEventCloudOutboxStripsCalendarIdentifier() throws {
        let database = try AppDatabase.openTemporary()
        let store = CountdownStore(db: database)
        var draft = try ManagedEventDraft(
            title: "生日",
            calendarIdentifier: "local-calendar",
            date: "2026-01-01"
        ).validated()
        draft.calendarIdentifier = "local-calendar"
        try store.persistManaged(ManagedEventRecord(draft: draft, modifiedByDevice: database.deviceID))
        let json = try store.pendingOutbox().first?.payloadJSON ?? ""
        XCTAssertFalse(json.contains("local-calendar"))
        XCTAssertFalse(json.contains("calendarIdentifier"))
        try database.close()
    }

    func testCloudKitSyncEngineRequiresProfileSession() throws {
        let database = try AppDatabase.openTemporary()
        let session = CloudProfileSession()
        let engine = CloudKitSyncEngine(database: database, session: session)
        XCTAssertEqual(engine.session.profile.mode, .localOnly)
        let outcome = try engine.database.lastFetchAt()
        XCTAssertNil(outcome)
        try database.recordFetchOutcome(.failed)
        XCTAssertNil(try engine.database.lastFetchAt())
        try database.close()
    }

    func testAppBrokerAlwaysCreatesEngineWithProfileSession() throws {
        let session = CloudProfileSession()
        let broker = try AppBroker.temporary(session: session)
        XCTAssertTrue(broker.syncEngine.session === session)
        XCTAssertEqual(broker.session.profile.mode, .localOnly)
        try broker.database.close()
    }

    func testSyncNowDoesNotAdvanceLastFetchAtWhenFetchFails() async throws {
        let session = CloudProfileSession(profile: CloudProfile(mode: .iCloud, accountHash: "test-account"))
        let broker = try AppBroker.temporary(session: session)
        broker.syncEngine.fetchChangesOverride = { .failed }
        XCTAssertNil(try broker.database.lastFetchAt())
        do {
            try await broker.syncEngine.syncNow()
            XCTFail("fetch failure should throw")
        } catch CloudKitSyncError.fetchFailed {
            XCTAssertNil(try broker.database.lastFetchAt())
        }
        try broker.database.close()
    }

    func testTaskMissionHabitCRUD() throws {
        let database = try AppDatabase.openTemporary()
        let store = DomainStore(db: database)
        let mission = MissionRecord(title: "发布 2.0", modifiedByDevice: database.deviceID)
        try store.upsertMission(mission)
        let task = TaskRecord(title: "写 iOS 壳", missionID: mission.id, modifiedByDevice: database.deviceID)
        try store.upsertTask(task)
        XCTAssertEqual(try store.missions().count, 1)
        XCTAssertEqual(try store.tasks().count, 1)
        let habit = HabitRecord(title: "早起", modifiedByDevice: database.deviceID)
        try store.upsertHabit(habit)
        try store.upsertCheckIn(CheckInRecord(habitID: habit.id, modifiedByDevice: database.deviceID))
        XCTAssertEqual(try store.checkIns(habitID: habit.id).count, 1)
        try database.close()
    }
}
