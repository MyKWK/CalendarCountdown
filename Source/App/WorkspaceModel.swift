import CalendarCountdownCalendar
import CalendarCountdownCore
import CalendarCountdownPersistence
import Combine
import Foundation

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var taskViews: [TaskOccurrenceView] = []
    @Published private(set) var missions: [MissionWriteResult] = []
    @Published private(set) var habits: [HabitWriteResult] = []
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published private(set) var databaseError: String?
    @Published var isLoading = false

    @Published private(set) var cloudMode: CloudSyncMode = .localOnly
    @Published private(set) var workspace: Workspace?
    var projectionRuntime: AppleProjectionRuntime?
    var onEnableCloudKit: (() -> Void)?
    private var isReconcilingProjections = false

    init(workspace: Workspace? = nil) {
        if let workspace {
            self.workspace = workspace
        } else {
            do {
                self.workspace = try Workspace.shared()
            } catch {
                self.workspace = nil
                databaseError = error.localizedDescription
            }
        }
    }

    func reload() {
        guard let workspace else { return }
        let started = Date()
        isLoading = true
        defer { isLoading = false }
        do {
            taskViews = try workspace.tasks.list(TaskListFilter(limit: 500))
            missions = try workspace.missions.list()
            habits = try workspace.habits.list()
            cloudMode = (try? workspace.cloud.mode()) ?? .localOnly
            if let snapshot = try? workspace.widgetSnapshotV2() {
                try? WidgetSnapshotV2.save(snapshot)
            }
            try? workspace.countdown.refreshLegacyJSONMirror()
            DiagnosticLogger.shared.log(
                .debug,
                category: .lifecycle,
                event: "workspace.reload.completed",
                metadata: [
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                    "tasks": String(taskViews.count),
                    "missions": String(missions.count),
                    "habits": String(habits.count),
                    "cloud_mode": cloudMode.rawValue
                ]
            )
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .lifecycle,
                event: "workspace.reload.failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            errorMessage = error.localizedDescription
        }
    }

    var openTasks: [TaskOccurrenceView] {
        taskViews.filter { $0.occurrence.status == .open }
    }

    var inboxTasks: [TaskOccurrenceView] {
        openTasks.filter { $0.occurrence.plannedDue == nil && $0.occurrence.plannedStart == nil }
    }

    var plannedTasks: [TaskOccurrenceView] {
        openTasks.filter { $0.occurrence.plannedDue != nil || $0.occurrence.plannedStart != nil }
    }

    var completedTasks: [TaskOccurrenceView] {
        taskViews.filter { $0.occurrence.status == .completed }
    }

    var overdueTasks: [TaskOccurrenceView] {
        openTasks.filter(\.isOverdue)
    }

    var todayTasks: [TaskOccurrenceView] {
        let calendar = Calendar.current
        return plannedTasks.filter { view in
            if let due = view.occurrence.plannedDue {
                return calendar.isDateInToday(due) || view.isOverdue
            }
            if let start = view.occurrence.plannedStart {
                return calendar.isDateInToday(start)
            }
            return false
        }
    }

    func createTask(_ command: CreateTaskCommand) {
        perform("已创建任务") {
            _ = try $0.tasks.create(command)
        }
    }

    func updateTask(occurrenceID: UUID, command: PatchTaskCommand) {
        perform("已更新任务") {
            _ = try $0.tasks.patch(occurrenceID: occurrenceID, command: command)
        }
    }

    func archiveTask(_ view: TaskOccurrenceView) {
        perform("已归档") {
            _ = try $0.tasks.archive(seriesID: view.series.id)
        }
    }

    func deleteTask(_ view: TaskOccurrenceView, permanent: Bool) {
        perform("已删除") {
            _ = try $0.tasks.delete(
                seriesID: view.series.id,
                permanent: permanent,
                confirmID: permanent ? view.series.id : nil
            )
        }
    }

    func complete(_ view: TaskOccurrenceView) {
        perform("已完成") {
            _ = try $0.tasks.complete(occurrenceID: view.occurrence.id)
        }
    }

    func reopen(_ view: TaskOccurrenceView) {
        perform("已重开") {
            _ = try $0.tasks.reopen(occurrenceID: view.occurrence.id)
        }
    }

    func skip(_ view: TaskOccurrenceView) {
        perform("已跳过") {
            _ = try $0.tasks.skip(occurrenceID: view.occurrence.id)
        }
    }

    func createMission(_ command: CreateMissionCommand) {
        perform("已创建使命") {
            _ = try $0.missions.create(command)
        }
    }

    func patchMission(id: UUID, command: PatchMissionCommand) {
        perform("已更新使命") {
            _ = try $0.missions.patch(id: id, command: command)
        }
    }

    func pauseMission(_ mission: MissionDefinition) {
        perform("已暂停使命") {
            _ = try $0.missions.pause(id: mission.id)
        }
    }

    func archiveMission(_ mission: MissionDefinition) {
        perform("已归档使命") {
            _ = try $0.missions.archive(id: mission.id)
        }
    }

    func completeMission(_ mission: MissionDefinition) {
        perform("已完成使命") {
            _ = try $0.missions.complete(id: mission.id)
        }
    }

    func createHabit(_ command: CreateHabitCommand) {
        perform("已创建习惯") {
            _ = try $0.habits.create(command)
        }
    }

    func undoCheckIn(_ item: HabitWriteResult) {
        guard let id = item.checkIn?.id else { return }
        perform("已撤销打卡") {
            _ = try $0.habits.undoCheckIn(id: id)
        }
    }

    func skipHabit(_ habit: HabitDefinition) {
        perform("已跳过本日") {
            let key = HabitStatisticsEngine.periodKey(
                for: Date(),
                schedule: habit.schedule,
                timeZone: .current
            )
            guard let key else { return }
            _ = try $0.habits.skipPeriod(habitID: habit.id, periodKey: key)
        }
    }

    func replaceWorkspace(_ workspace: Workspace) {
        self.workspace = workspace
        reload()
    }

    func setProjectTasks(_ enabled: Bool) {
        perform(enabled ? "已开启任务投影" : "已关闭任务投影") {
            try $0.setProjectionSettings(projectTasks: enabled)
        }
    }

    func setProjectHabits(_ enabled: Bool) {
        perform(enabled ? "已开启习惯投影" : "已关闭习惯投影") {
            try $0.setProjectionSettings(projectHabits: enabled)
        }
    }

    func setProjectMissions(_ enabled: Bool) {
        perform(enabled ? "已开启使命投影" : "已关闭使命投影") {
            try $0.setProjectionSettings(projectMissions: enabled)
        }
    }

    func setCloudMode(_ enabled: Bool) {
        perform(enabled ? "已开启 iCloud 同步" : "已关闭 iCloud 同步") {
            try $0.cloud.setMode(enabled ? .iCloud : .localOnly)
        }
        if enabled, cloudMode == .iCloud {
            onEnableCloudKit?()
        }
    }

    func reconcileProjections() async {
        guard let workspace, let projectionRuntime else { return }
        guard !isReconcilingProjections else { return }
        isReconcilingProjections = true
        defer { isReconcilingProjections = false }
        let operationID = UUID()
        do {
            let report = try await workspace.reconcileProjections(using: projectionRuntime)
            DiagnosticLogger.shared.log(
                report.failed == 0 ? .notice : .warning,
                category: .projection,
                event: "projection.reconcile.completed",
                correlationID: operationID,
                metadata: [
                    "desired": String(report.desired),
                    "applied": String(report.applied),
                    "reverse_actions": String(report.reverseActions),
                    "missing": String(report.missing),
                    "drifted": String(report.drifted),
                    "failed": String(report.failed)
                ]
            )
            reload()
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .projection,
                event: "projection.reconcile.failed",
                correlationID: operationID,
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            errorMessage = error.localizedDescription
        }
    }

    func checkIn(_ habit: HabitDefinition, value: Decimal? = nil, fillToTarget: Bool = false, at: Date? = nil) {
        perform("已打卡") {
            _ = try $0.habits.checkIn(habitID: habit.id, value: value, at: at, fillToTarget: fillToTarget)
        }
    }

    private func perform(_ status: String, _ work: (Workspace) throws -> Void) {
        guard let workspace else {
            errorMessage = databaseError ?? "数据库不可用。"
            return
        }
        do {
            try work(workspace)
            DiagnosticLogger.shared.log(
                .notice,
                category: .command,
                event: "app.command.completed",
                metadata: ["status_context": status]
            )
            statusMessage = status
            reload()
            Task { await reconcileProjections() }
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .command,
                event: "app.command.failed",
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "status_context": status
                ]) { current, _ in current }
            )
            errorMessage = error.localizedDescription
        }
    }
}
