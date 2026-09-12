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
    @Published private(set) var cloudStatus: CloudSyncStatus?
    @Published var isCloudSyncing = false
    @Published var cloudErrorMessage: String?
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
            missions = try workspace.missions.list().filter { $0.mission.status != .archived }
            habits = try workspace.habits.list()
            cloudMode = (try? workspace.cloud.mode()) ?? .localOnly
            cloudStatus = try? workspace.cloud.status()
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

    var unassignedTaskSeries: [TaskSeries] {
        var seen = Set<UUID>()
        var result: [TaskSeries] = []
        for view in taskViews {
            let series = view.series
            guard series.missionID == nil, series.deletedAt == nil else { continue }
            guard seen.insert(series.id).inserted else { continue }
            result.append(series)
        }
        return result
    }

    /// Picks the least-used identity color so consecutive missions are easy to distinguish.
    var suggestedMissionColor: MissionColor {
        let counts = Dictionary(grouping: missions.map { MissionColor.resolve($0.mission.color) }, by: { $0 })
            .mapValues(\.count)
        return MissionColor.allCases.min { lhs, rhs in
            let left = counts[lhs, default: 0]
            let right = counts[rhs, default: 0]
            if left != right { return left < right }
            let leftIndex = MissionColor.allCases.firstIndex(of: lhs) ?? 0
            let rightIndex = MissionColor.allCases.firstIndex(of: rhs) ?? 0
            return leftIndex < rightIndex
        } ?? .defaultValue
    }

    func mission(for id: UUID?) -> MissionDefinition? {
        guard let id else { return nil }
        return missions.first(where: { $0.mission.id == id })?.mission
    }

    func missionTitle(for id: UUID?) -> String? {
        mission(for: id)?.title
    }

    func missionActivity(for mission: MissionDefinition) -> [MissionActivityEntry] {
        guard let workspace else { return [] }
        do {
            return try workspace.missions.activity(id: mission.id)
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .lifecycle,
                event: "mission.activity.load.failed",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            return []
        }
    }

    var featuredMenuMission: MissionWriteResult? {
        let featured = MissionSelection.featured(among: missions.map(\.mission))
        guard let featured else { return nil }
        return missions.first(where: { $0.mission.id == featured.id })
    }

    func taskViews(forMissionID id: UUID) -> [TaskOccurrenceView] {
        taskViews
            .filter { $0.series.missionID == id && $0.series.deletedAt == nil }
            .sorted { lhs, rhs in
                let leftOpen = lhs.occurrence.status == .open
                let rightOpen = rhs.occurrence.status == .open
                if leftOpen != rightOpen { return leftOpen && !rightOpen }
                let leftDue = lhs.occurrence.plannedDue ?? .distantFuture
                let rightDue = rhs.occurrence.plannedDue ?? .distantFuture
                if leftDue != rightDue { return leftDue < rightDue }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
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

    func deleteMission(_ mission: MissionDefinition, permanent: Bool = false) {
        perform("已删除使命") {
            _ = try $0.missions.delete(
                id: mission.id,
                permanent: permanent,
                confirmID: permanent ? mission.id : nil
            )
        }
    }

    func reopenMission(_ mission: MissionDefinition) {
        perform("已重新开启使命") {
            _ = try $0.missions.setStatus(id: mission.id, status: .active)
        }
    }

    func attachTask(_ series: TaskSeries, to mission: MissionDefinition) {
        perform("已加入使命") {
            _ = try $0.missions.addTask(missionID: mission.id, seriesID: series.id)
        }
    }

    func detachTask(seriesID: UUID, from mission: MissionDefinition) {
        perform("已移出使命") {
            _ = try $0.missions.removeTask(missionID: mission.id, seriesID: seriesID)
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

    var cloudPresentation: CloudSyncPresentation {
        CloudSyncPresentation.resolve(
            mode: cloudMode,
            isSyncing: isCloudSyncing,
            hasError: cloudErrorMessage != nil,
            status: cloudStatus
        )
    }

    func setCloudMode(_ enabled: Bool) {
        cloudErrorMessage = nil
        isCloudSyncing = enabled
        perform(enabled ? "已开启 iCloud 同步" : "已关闭 iCloud 同步") {
            try $0.cloud.setMode(enabled ? .iCloud : .localOnly)
        }
        if enabled, cloudMode == .iCloud {
            onEnableCloudKit?()
        } else {
            isCloudSyncing = false
        }
        if enabled, cloudMode != .iCloud {
            isCloudSyncing = false
            cloudErrorMessage = errorMessage
        }
    }

    func markCloudSyncFinished(error: String?) {
        isCloudSyncing = false
        if let error {
            cloudErrorMessage = error
            errorMessage = error
            statusMessage = nil
        } else if cloudErrorMessage != nil, errorMessage == cloudErrorMessage {
            errorMessage = nil
            cloudErrorMessage = nil
        } else {
            cloudErrorMessage = nil
        }
        reload()
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
