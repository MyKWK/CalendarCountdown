import Foundation

public enum MissionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case archived
}

public struct MissionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var status: MissionStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: MissionStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }
}

public struct TaskRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var missionID: UUID?
    public var workload: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        missionID: UUID? = nil,
        workload: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.missionID = missionID
        self.workload = max(1, workload)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }
}

public struct HabitRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }
}

public struct CheckInRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var habitID: UUID
    public var occurredOn: Date
    public var note: String
    public var createdAt: Date
    public var revision: Int64
    public var modifiedByDevice: UUID
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        habitID: UUID,
        occurredOn: Date = Date(),
        note: String = "",
        createdAt: Date = Date(),
        revision: Int64 = 1,
        modifiedByDevice: UUID,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.habitID = habitID
        self.occurredOn = occurredOn
        self.note = note
        self.createdAt = createdAt
        self.revision = revision
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }
}

public struct MissionProgress: Equatable, Sendable {
    public var missionID: UUID
    public var plannedWorkload: Int
    public var completedWorkload: Int

    public var ratio: Double {
        guard plannedWorkload > 0 else { return 0 }
        return Double(completedWorkload) / Double(plannedWorkload)
    }

    public init(missionID: UUID, plannedWorkload: Int, completedWorkload: Int) {
        self.missionID = missionID
        self.plannedWorkload = plannedWorkload
        self.completedWorkload = completedWorkload
    }

    public static func calculate(missionID: UUID, tasks: [TaskRecord]) -> MissionProgress {
        let members = tasks.filter { $0.missionID == missionID && $0.deletedAt == nil }
        let planned = members.reduce(0) { $0 + $1.workload }
        let completed = members.filter(\.isCompleted).reduce(0) { $0 + $1.workload }
        return MissionProgress(missionID: missionID, plannedWorkload: planned, completedWorkload: completed)
    }
}

public enum RFC3339 {
    public static func utcString(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return formatter.date(from: value) ?? fractionalFormatter.date(from: value)
    }

    public static func parseRequired(_ value: String) throws -> Date {
        guard let date = parse(value) else {
            throw DomainStoreError.invalidDate(value)
        }
        return date
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

public enum DomainStoreError: LocalizedError {
    case invalidDate(String)
    case recordNotFound(UUID)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDate(value):
            "无效的日期：\(value)。"
        case let .recordNotFound(id):
            "找不到记录：\(id.uuidString)。"
        case let .sqlite(message):
            message
        }
    }
}
