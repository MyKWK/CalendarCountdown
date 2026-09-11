import Foundation

public enum TaskKind: String, Codable, CaseIterable, Sendable {
    case deadline
    case timeWindow
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high

    public var eventKitPriority: Int {
        switch self {
        case .none: 0
        case .high: 1
        case .medium: 5
        case .low: 9
        }
    }
}

public enum WorkloadPoints: Int, Codable, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5
    case eight = 8
}

public enum ProjectionPolicy: String, Codable, CaseIterable, Sendable {
    case none
    case reminder
    case calendar
    case both

    public var projectsReminder: Bool {
        self == .reminder || self == .both
    }

    public var projectsEvent: Bool {
        self == .calendar || self == .both
    }
}

public enum TaskOccurrenceStatus: String, Codable, CaseIterable, Sendable {
    case open
    case completed
    case canceled
    case skipped

    public var countsAsDone: Bool { self == .completed }
    public var isTerminal: Bool { self != .open }
}

public enum OccurrenceDisposition: String, Codable, CaseIterable, Sendable {
    case planned
    case excludedFromProgress
    case archived
}

public struct AlertSpec: Equatable, Codable, Sendable {
    public var secondsBefore: Int

    public init(secondsBefore: Int) {
        self.secondsBefore = secondsBefore
    }

    public func validated() throws -> AlertSpec {
        guard secondsBefore >= 0, secondsBefore <= 365 * 24 * 60 * 60 else {
            throw DomainError.validation("提醒偏移必须在 0 到 365 天之间。")
        }
        return self
    }
}

public struct TaskSchedule: Equatable, Codable, Sendable {
    public var timeZoneIdentifier: String
    public var isAllDay: Bool
    public var plannedStart: Date?
    public var plannedDue: Date?

    public init(
        timeZoneIdentifier: String,
        isAllDay: Bool = false,
        plannedStart: Date? = nil,
        plannedDue: Date? = nil
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isAllDay = isAllDay
        self.plannedStart = plannedStart
        self.plannedDue = plannedDue
    }

    public var isUndated: Bool {
        plannedStart == nil && plannedDue == nil
    }

    public func validated(kind: TaskKind) throws -> TaskSchedule {
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw DomainError.validation(
                "无效的 IANA 时区：\(timeZoneIdentifier)。",
                details: ["timeZone": timeZoneIdentifier]
            )
        }
        if kind == .timeWindow {
            guard let start = plannedStart, let due = plannedDue, due >= start else {
                throw DomainError.validation("时间段任务必须提供开始和结束时间，且结束不早于开始。")
            }
        }
        return self
    }
}

public struct TaskSeries: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var markdownDescription: String?
    public var kind: TaskKind
    public var missionID: UUID?
    public var priority: TaskPriority
    public var workload: WorkloadPoints
    public var schedule: TaskSchedule
    public var recurrence: RecurrenceSpec?
    public var alerts: [AlertSpec]
    public var projectionPolicy: ProjectionPolicy
    public var sortKey: String
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        markdownDescription: String? = nil,
        kind: TaskKind,
        missionID: UUID? = nil,
        priority: TaskPriority = .none,
        workload: WorkloadPoints = .one,
        schedule: TaskSchedule,
        recurrence: RecurrenceSpec? = nil,
        alerts: [AlertSpec] = [],
        projectionPolicy: ProjectionPolicy = .none,
        sortKey: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.markdownDescription = markdownDescription
        self.kind = kind
        self.missionID = missionID
        self.priority = priority
        self.workload = workload
        self.schedule = schedule
        self.recurrence = recurrence
        self.alerts = alerts
        self.projectionPolicy = projectionPolicy
        self.sortKey = sortKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }

    public var isInfinite: Bool {
        recurrence?.isInfinite == true
    }

    public func validated() throws -> TaskSeries {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.markdownDescription = markdownDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.title.isEmpty else {
            throw DomainError.validation("任务标题不能为空。")
        }
        copy.schedule = try copy.schedule.validated(kind: copy.kind)
        copy.recurrence = try copy.recurrence?.validated()
        copy.alerts = try copy.alerts.map { try $0.validated() }
        if copy.sortKey.isEmpty {
            copy.sortKey = RFC3339.utcString(from: copy.createdAt) + copy.id.uuidString.lowercased()
        }
        return copy
    }
}

public struct TaskOccurrence: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var seriesID: UUID
    public var occurrenceKey: String
    public var titleOverride: String?
    public var descriptionOverrideMarkdown: String?
    public var plannedStart: Date?
    public var plannedDue: Date?
    public var status: TaskOccurrenceStatus
    public var completedAt: Date?
    public var disposition: OccurrenceDisposition
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        seriesID: UUID,
        occurrenceKey: String,
        titleOverride: String? = nil,
        descriptionOverrideMarkdown: String? = nil,
        plannedStart: Date? = nil,
        plannedDue: Date? = nil,
        status: TaskOccurrenceStatus = .open,
        completedAt: Date? = nil,
        disposition: OccurrenceDisposition = .planned,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.occurrenceKey = occurrenceKey
        self.titleOverride = titleOverride
        self.descriptionOverrideMarkdown = descriptionOverrideMarkdown
        self.plannedStart = plannedStart
        self.plannedDue = plannedDue
        self.status = status
        self.completedAt = completedAt
        self.disposition = disposition
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }

    public func isOverdue(now: Date) -> Bool {
        status == .open && (plannedDue.map { $0 < now } ?? false)
    }

    public func displayTitle(seriesTitle: String) -> String {
        let trimmed = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? seriesTitle : trimmed
    }
}

public enum EditScope: String, Codable, CaseIterable, Sendable {
    case thisOccurrence = "this"
    case thisAndFuture = "future"
    case series
}

public struct TaskOccurrenceView: Equatable, Codable, Identifiable, Sendable {
    public var occurrence: TaskOccurrence
    public var series: TaskSeries

    public var id: UUID { occurrence.id }

    public init(occurrence: TaskOccurrence, series: TaskSeries) {
        self.occurrence = occurrence
        self.series = series
    }

    public var title: String {
        occurrence.displayTitle(seriesTitle: series.title)
    }

    public var markdownDescription: String? {
        occurrence.descriptionOverrideMarkdown ?? series.markdownDescription
    }

    public var workload: WorkloadPoints { series.workload }

    public var isOverdue: Bool {
        occurrence.isOverdue(now: Date())
    }
}
