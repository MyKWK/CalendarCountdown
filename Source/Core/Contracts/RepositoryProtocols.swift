import Foundation

public enum ProjectionKind: String, Codable, CaseIterable, Sendable {
    case reminder
    case event
    case reminderList
}

public enum ProjectionBindingState: String, Codable, CaseIterable, Sendable {
    case synced
    case missing
    case drifted
    case pending
    case failed
}

public enum ReconciliationClassification: String, Codable, Sendable {
    case projectedCoreChange
    case adoptedNativeAction
    case projectionDrift
    case missingProjection
    case conflict
}

public struct ProjectionSettings: Equatable, Codable, Sendable {
    public var id: UUID
    public var projectTasks: Bool
    public var projectHabits: Bool
    public var projectMissions: Bool
    public var acceptNativeCompletion: Bool
    public var acceptNativeScheduleChanges: Bool
    public var revision: Int64
    public var updatedAt: Date
    public var modifiedByDevice: UUID

    public init(
        id: UUID,
        projectTasks: Bool,
        projectHabits: Bool,
        projectMissions: Bool,
        acceptNativeCompletion: Bool,
        acceptNativeScheduleChanges: Bool,
        revision: Int64,
        updatedAt: Date,
        modifiedByDevice: UUID
    ) {
        self.id = id
        self.projectTasks = projectTasks
        self.projectHabits = projectHabits
        self.projectMissions = projectMissions
        self.acceptNativeCompletion = acceptNativeCompletion
        self.acceptNativeScheduleChanges = acceptNativeScheduleChanges
        self.revision = revision
        self.updatedAt = updatedAt
        self.modifiedByDevice = modifiedByDevice
    }

    public static func `default`(deviceID: UUID, now: Date = Date()) -> ProjectionSettings {
        ProjectionSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            projectTasks: false,
            projectHabits: false,
            projectMissions: false,
            acceptNativeCompletion: true,
            acceptNativeScheduleChanges: false,
            revision: 1,
            updatedAt: now,
            modifiedByDevice: deviceID
        )
    }
}

public struct DesiredProjection: Equatable, Sendable {
    public var domainType: String
    public var domainID: UUID
    public var projectionKind: ProjectionKind
    public var title: String
    public var notes: String?
    public var url: String
    public var start: Date?
    public var due: Date?
    public var isAllDay: Bool
    public var completed: Bool
    public var priority: TaskPriority
    public var revision: Int64

    public init(
        domainType: String,
        domainID: UUID,
        projectionKind: ProjectionKind,
        title: String,
        notes: String? = nil,
        url: String,
        start: Date? = nil,
        due: Date? = nil,
        isAllDay: Bool = false,
        completed: Bool = false,
        priority: TaskPriority = .none,
        revision: Int64
    ) {
        self.domainType = domainType
        self.domainID = domainID
        self.projectionKind = projectionKind
        self.title = title
        self.notes = notes
        self.url = url
        self.start = start
        self.due = due
        self.isAllDay = isAllDay
        self.completed = completed
        self.priority = priority
        self.revision = revision
    }
}

public enum ProjectionPlanner {
    public static func desired(
        series: TaskSeries,
        occurrence: TaskOccurrence,
        settings: ProjectionSettings
    ) -> [DesiredProjection] {
        guard settings.projectTasks, series.projectionPolicy != .none else { return [] }
        guard occurrence.deletedAt == nil, series.deletedAt == nil else { return [] }
        guard occurrence.status != .canceled && occurrence.status != .skipped else { return [] }
        let title = occurrence.displayTitle(seriesTitle: series.title)
        let notes = occurrence.descriptionOverrideMarkdown ?? series.markdownDescription
        let url = DomainLink.task(series.id, occurrenceKey: occurrence.occurrenceKey).urlString
        var result: [DesiredProjection] = []
        if series.projectionPolicy.projectsReminder {
            result.append(
                DesiredProjection(
                    domainType: "task_occurrence",
                    domainID: occurrence.id,
                    projectionKind: .reminder,
                    title: title,
                    notes: notes,
                    url: url,
                    start: occurrence.plannedStart,
                    due: occurrence.plannedDue,
                    isAllDay: series.schedule.isAllDay,
                    completed: occurrence.status == .completed,
                    priority: series.priority,
                    revision: max(series.revision, occurrence.revision)
                )
            )
        }
        if series.kind == .timeWindow, series.projectionPolicy.projectsEvent {
            result.append(
                DesiredProjection(
                    domainType: "task_occurrence",
                    domainID: occurrence.id,
                    projectionKind: .event,
                    title: title,
                    notes: notes,
                    url: url,
                    start: occurrence.plannedStart,
                    due: occurrence.plannedDue,
                    isAllDay: series.schedule.isAllDay,
                    completed: occurrence.status == .completed,
                    priority: series.priority,
                    revision: max(series.revision, occurrence.revision)
                )
            )
        }
        return result
    }

    public static func desired(
        habit: HabitDefinition,
        settings: ProjectionSettings,
        period: HabitPeriod? = nil
    ) -> [DesiredProjection] {
        guard settings.projectHabits, habit.projectionPolicy != .none, habit.deletedAt == nil else { return [] }
        var result: [DesiredProjection] = []
        if habit.projectionPolicy.projectsReminder {
            result.append(
                DesiredProjection(
                    domainType: "habit",
                    domainID: habit.id,
                    projectionKind: .reminder,
                    title: habit.title,
                    notes: habit.markdownDescription,
                    url: DomainLink.habit(habit.id).urlString,
                    completed: period?.disposition == .completed,
                    revision: max(habit.revision, period?.revision ?? 0)
                )
            )
        }
        return result
    }

    public static func desired(
        mission: MissionDefinition,
        settings: ProjectionSettings
    ) -> [DesiredProjection] {
        guard settings.projectMissions, mission.deletedAt == nil else { return [] }
        guard mission.status != .archived else { return [] }
        let url = DomainLink.mission(mission.id).urlString
        let due = mission.targetDate?.startOfDay(in: TimeZone.current)
        var result: [DesiredProjection] = []
        result.append(
            DesiredProjection(
                domainType: "mission",
                domainID: mission.id,
                projectionKind: .reminder,
                title: mission.title,
                notes: mission.markdownDescription,
                url: url,
                due: due,
                completed: mission.status == .completed,
                revision: mission.revision
            )
        )
        if let due {
            result.append(
                DesiredProjection(
                    domainType: "mission",
                    domainID: mission.id,
                    projectionKind: .event,
                    title: mission.title,
                    notes: mission.markdownDescription,
                    url: url,
                    start: due,
                    due: due,
                    isAllDay: true,
                    completed: mission.status == .completed,
                    revision: mission.revision
                )
            )
        }
        return result
    }
}

public protocol TaskQuerying: Sendable {
    func taskSeries(id: UUID) throws -> TaskSeries?
    func occurrence(id: UUID) throws -> TaskOccurrence?
    func occurrence(key: String) throws -> TaskOccurrence?
}

public protocol MissionQuerying: Sendable {
    func mission(id: UUID) throws -> MissionDefinition?
}

public protocol HabitQuerying: Sendable {
    func habit(id: UUID) throws -> HabitDefinition?
    func checkIn(id: UUID) throws -> CheckInRecord?
}

public protocol ProjectionApplying: Sendable {
    func nativeItems() async throws -> [ProjectedNativeItem]
    func apply(_ desired: DesiredProjection) async throws -> String
    func remove(url: String, kind: ProjectionKind) async throws
}

public struct NullProjectionApplier: ProjectionApplying {
    public init() {}

    public func nativeItems() async throws -> [ProjectedNativeItem] { [] }

    public func apply(_ desired: DesiredProjection) async throws -> String {
        throw DomainError(
            code: .projectionFailed,
            message: "未注入投影执行器，无法写入 Apple 提醒事项或日历。"
        )
    }

    public func remove(url: String, kind: ProjectionKind) async throws {}
}
