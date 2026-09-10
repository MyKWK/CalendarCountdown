#if canImport(CalendarCountdownCore)
import CalendarCountdownCore
#endif
import Combine
import Foundation
#if canImport(CalendarCountdownPersistence)
import CalendarCountdownPersistence
#endif

@MainActor
public final class WorkspaceModel: ObservableObject {
    @Published public private(set) var missions: [MissionRecord] = []
    @Published public private(set) var tasks: [TaskRecord] = []
    @Published public private(set) var habits: [HabitRecord] = []
    @Published public var errorMessage: String?

    public let database: AppDatabase
    private let store: DomainStore
    private let countdownStore: CountdownStore

    public init(database: AppDatabase) {
        self.database = database
        self.store = DomainStore(db: database)
        self.countdownStore = CountdownStore(db: database)
    }

    public var openTasks: [TaskRecord] {
        tasks.filter { !$0.isCompleted }
    }

    public func progress(for mission: MissionRecord) -> MissionProgress {
        MissionProgress.calculate(missionID: mission.id, tasks: tasks)
    }

    public func reload() throws {
        missions = try store.missions()
        tasks = try store.tasks()
        habits = try store.habits()
    }

    public func addMission(title: String, notes: String = "") throws {
        let record = MissionRecord(title: title, notes: notes, modifiedByDevice: database.deviceID)
        try store.upsertMission(record)
        try reload()
    }

    public func deleteMission(_ mission: MissionRecord) throws {
        var next = mission
        next.deletedAt = Date()
        next.updatedAt = Date()
        next.revision += 1
        next.modifiedByDevice = database.deviceID
        try store.upsertMission(next)
        try reload()
    }

    public func addTask(title: String, dueDate: Date?, missionID: UUID?) throws {
        let record = TaskRecord(
            title: title,
            dueDate: dueDate,
            missionID: missionID,
            modifiedByDevice: database.deviceID
        )
        try store.upsertTask(record)
        try reload()
    }

    public func toggleTask(_ task: TaskRecord) throws {
        var next = task
        next.isCompleted.toggle()
        next.completedAt = next.isCompleted ? Date() : nil
        next.updatedAt = Date()
        next.revision += 1
        next.modifiedByDevice = database.deviceID
        try store.upsertTask(next)
        try reload()
    }

    public func deleteTask(_ task: TaskRecord) throws {
        var next = task
        next.deletedAt = Date()
        next.updatedAt = Date()
        next.revision += 1
        try store.upsertTask(next)
        try reload()
    }

    public func addHabit(title: String) throws {
        try store.upsertHabit(HabitRecord(title: title, modifiedByDevice: database.deviceID))
        try reload()
    }

    public func deleteHabit(_ habit: HabitRecord) throws {
        var next = habit
        next.deletedAt = Date()
        next.updatedAt = Date()
        next.revision += 1
        next.modifiedByDevice = database.deviceID
        try store.upsertHabit(next)
        try reload()
    }

    public func checkIn(habit: HabitRecord, on day: Date = Date()) throws {
        try store.upsertCheckIn(
            CheckInRecord(habitID: habit.id, occurredOn: day, modifiedByDevice: database.deviceID)
        )
        try reload()
    }

    public func checkIns(for habit: HabitRecord) throws -> [CheckInRecord] {
        try store.checkIns(habitID: habit.id)
    }

    public func mirrorCountdownSelection(_ selection: CountdownSelection) {
        var copy = selection
        copy.modifiedByDevice = database.deviceID
        copy.updatedAt = Date()
        try? countdownStore.persistSelection(copy)
    }

    public func mirrorCountdownPreferences(_ preferences: CountdownDisplayPreferences) {
        try? countdownStore.persistPreferences(preferences)
    }
}
