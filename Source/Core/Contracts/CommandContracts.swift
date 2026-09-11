import Foundation

public enum CommandActor: String, Codable, CaseIterable, Sendable {
    case app
    case cli
    case mcp
    case appleCompletion
    case system
    case `import`
}

public enum ProjectionEffectKind: String, Codable, Sendable {
    case none
    case planned
    case succeeded
    case failed
    case skipped
}

public struct ProjectionEffect: Equatable, Codable, Sendable {
    public var kind: ProjectionEffectKind
    public var projectionKind: String?
    public var appleIdentifier: String?
    public var code: String?
    public var reason: String?

    public init(
        kind: ProjectionEffectKind,
        projectionKind: String? = nil,
        appleIdentifier: String? = nil,
        code: String? = nil,
        reason: String? = nil
    ) {
        self.kind = kind
        self.projectionKind = projectionKind
        self.appleIdentifier = appleIdentifier
        self.code = code
        self.reason = reason
    }

    public static let none = ProjectionEffect(kind: .none)

    public static func planned(_ projectionKind: String) -> ProjectionEffect {
        ProjectionEffect(kind: .planned, projectionKind: projectionKind)
    }

    public static func skipped(_ reason: String) -> ProjectionEffect {
        ProjectionEffect(kind: .skipped, reason: reason)
    }
}

public struct WriteEffects: Equatable, Codable, Sendable {
    public var sqliteCommitted: Bool
    public var cloudOutboxRecordNames: [String]
    public var reminder: ProjectionEffect
    public var event: ProjectionEffect
    public var dryRun: Bool

    public init(
        sqliteCommitted: Bool,
        cloudOutboxRecordNames: [String] = [],
        reminder: ProjectionEffect = .none,
        event: ProjectionEffect = .none,
        dryRun: Bool = false
    ) {
        self.sqliteCommitted = sqliteCommitted
        self.cloudOutboxRecordNames = cloudOutboxRecordNames
        self.reminder = reminder
        self.event = event
        self.dryRun = dryRun
    }
}

public struct WriteOptions: Equatable, Sendable {
    public var dryRun: Bool
    public var idempotencyKey: String?
    public var ifRevision: Int64?
    public var requestID: UUID
    public var actor: CommandActor
    public var now: Date

    public init(
        dryRun: Bool = false,
        idempotencyKey: String? = nil,
        ifRevision: Int64? = nil,
        requestID: UUID = UUID(),
        actor: CommandActor = .app,
        now: Date = Date()
    ) {
        self.dryRun = dryRun
        self.idempotencyKey = idempotencyKey
        self.ifRevision = ifRevision
        self.requestID = requestID
        self.actor = actor
        self.now = now
    }
}

public struct CreateTaskCommand: Equatable, Codable, Sendable {
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

    public init(
        title: String,
        markdownDescription: String? = nil,
        kind: TaskKind = .deadline,
        missionID: UUID? = nil,
        priority: TaskPriority = .none,
        workload: WorkloadPoints = .one,
        schedule: TaskSchedule,
        recurrence: RecurrenceSpec? = nil,
        alerts: [AlertSpec] = [],
        projectionPolicy: ProjectionPolicy = .none
    ) {
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
    }
}

public struct PatchTaskCommand: Equatable, Codable, Sendable {
    public var title: String?
    public var markdownDescription: String?
    public var kind: TaskKind?
    public var missionID: UUID?
    public var clearMission: Bool?
    public var priority: TaskPriority?
    public var workload: WorkloadPoints?
    public var schedule: TaskSchedule?
    public var recurrence: RecurrenceSpec?
    public var clearRecurrence: Bool?
    public var alerts: [AlertSpec]?
    public var projectionPolicy: ProjectionPolicy?
    public var scope: EditScope
    public var migrateHistory: Bool

    public init(
        title: String? = nil,
        markdownDescription: String? = nil,
        kind: TaskKind? = nil,
        missionID: UUID? = nil,
        clearMission: Bool? = nil,
        priority: TaskPriority? = nil,
        workload: WorkloadPoints? = nil,
        schedule: TaskSchedule? = nil,
        recurrence: RecurrenceSpec? = nil,
        clearRecurrence: Bool? = nil,
        alerts: [AlertSpec]? = nil,
        projectionPolicy: ProjectionPolicy? = nil,
        scope: EditScope = .thisOccurrence,
        migrateHistory: Bool = false
    ) {
        self.title = title
        self.markdownDescription = markdownDescription
        self.kind = kind
        self.missionID = missionID
        self.clearMission = clearMission
        self.priority = priority
        self.workload = workload
        self.schedule = schedule
        self.recurrence = recurrence
        self.clearRecurrence = clearRecurrence
        self.alerts = alerts
        self.projectionPolicy = projectionPolicy
        self.scope = scope
        self.migrateHistory = migrateHistory
    }
}

public struct CreateMissionCommand: Equatable, Codable, Sendable {
    public var title: String
    public var markdownDescription: String?
    public var color: String
    public var icon: String
    public var status: MissionStatus
    public var targetDate: LocalDate?
    public var defaultWorkload: WorkloadPoints

    public init(
        title: String,
        markdownDescription: String? = nil,
        color: String = "#5B8DEF",
        icon: String = "flag.fill",
        status: MissionStatus = .active,
        targetDate: LocalDate? = nil,
        defaultWorkload: WorkloadPoints = .one
    ) {
        self.title = title
        self.markdownDescription = markdownDescription
        self.color = color
        self.icon = icon
        self.status = status
        self.targetDate = targetDate
        self.defaultWorkload = defaultWorkload
    }
}

public struct PatchMissionCommand: Equatable, Codable, Sendable {
    public var title: String?
    public var markdownDescription: String?
    public var color: String?
    public var icon: String?
    public var status: MissionStatus?
    public var targetDate: LocalDate?
    public var clearTargetDate: Bool?
    public var defaultWorkload: WorkloadPoints?

    public init(
        title: String? = nil,
        markdownDescription: String? = nil,
        color: String? = nil,
        icon: String? = nil,
        status: MissionStatus? = nil,
        targetDate: LocalDate? = nil,
        clearTargetDate: Bool? = nil,
        defaultWorkload: WorkloadPoints? = nil
    ) {
        self.title = title
        self.markdownDescription = markdownDescription
        self.color = color
        self.icon = icon
        self.status = status
        self.targetDate = targetDate
        self.clearTargetDate = clearTargetDate
        self.defaultWorkload = defaultWorkload
    }
}

public struct PatchHabitCommand: Equatable, Codable, Sendable {
    public var title: String?
    public var markdownDescription: String?
    public var targetValue: Decimal?
    public var unit: String?
    public var schedule: HabitSchedule?
    public var reminderTimes: [String]?
    public var allowBackfillDays: Int?
    public var completionPolicy: HabitCompletionPolicy?
    public var projectionPolicy: ProjectionPolicy?
    public var activeUntil: LocalDate?
    public var clearActiveUntil: Bool?

    public init(
        title: String? = nil,
        markdownDescription: String? = nil,
        targetValue: Decimal? = nil,
        unit: String? = nil,
        schedule: HabitSchedule? = nil,
        reminderTimes: [String]? = nil,
        allowBackfillDays: Int? = nil,
        completionPolicy: HabitCompletionPolicy? = nil,
        projectionPolicy: ProjectionPolicy? = nil,
        activeUntil: LocalDate? = nil,
        clearActiveUntil: Bool? = nil
    ) {
        self.title = title
        self.markdownDescription = markdownDescription
        self.targetValue = targetValue
        self.unit = unit
        self.schedule = schedule
        self.reminderTimes = reminderTimes
        self.allowBackfillDays = allowBackfillDays
        self.completionPolicy = completionPolicy
        self.projectionPolicy = projectionPolicy
        self.activeUntil = activeUntil
        self.clearActiveUntil = clearActiveUntil
    }
}

public struct BrokerWriteOptions: Equatable, Codable, Sendable {
    public var dryRun: Bool
    public var idempotencyKey: String?
    public var ifRevision: Int64?
    public var requestID: UUID
    public var actor: CommandActor

    public init(
        dryRun: Bool = false,
        idempotencyKey: String? = nil,
        ifRevision: Int64? = nil,
        requestID: UUID = UUID(),
        actor: CommandActor = .cli
    ) {
        self.dryRun = dryRun
        self.idempotencyKey = idempotencyKey
        self.ifRevision = ifRevision
        self.requestID = requestID
        self.actor = actor
    }

    public func makeWriteOptions(now: Date = Date()) -> WriteOptions {
        WriteOptions(
            dryRun: dryRun,
            idempotencyKey: idempotencyKey,
            ifRevision: ifRevision,
            requestID: requestID,
            actor: actor,
            now: now
        )
    }

    public init(_ options: WriteOptions) {
        dryRun = options.dryRun
        idempotencyKey = options.idempotencyKey
        ifRevision = options.ifRevision
        requestID = options.requestID
        actor = options.actor
    }
}

public struct BrokerRequest: Equatable, Codable, Sendable {
    public var jsonrpc: String
    public var id: UUID
    public var method: String
    public var params: String
    public var token: String
    public var options: BrokerWriteOptions

    public init(
        jsonrpc: String = "2.0",
        id: UUID = UUID(),
        method: String,
        params: String = "{}",
        token: String,
        options: BrokerWriteOptions = BrokerWriteOptions()
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.token = token
        self.options = options
    }
}

public struct BrokerResponse: Equatable, Codable, Sendable {
    public var jsonrpc: String
    public var id: UUID
    public var ok: Bool
    public var resultJSON: String?
    public var error: APIErrorPayload?
    public var meta: APIMeta

    public init(
        jsonrpc: String = "2.0",
        id: UUID,
        ok: Bool,
        resultJSON: String? = nil,
        error: APIErrorPayload? = nil,
        meta: APIMeta = APIMeta()
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.ok = ok
        self.resultJSON = resultJSON
        self.error = error
        self.meta = meta
    }
}

public struct CapabilitiesReport: Equatable, Codable, Sendable {
    public var version: String
    public var schemaVersion: Int
    public var cloudKitMode: String
    public var cloudKitAccount: String
    public var entities: [String]
    public var sqlite: Bool
    public var mcp: Bool
    public var broker: Bool
    public var remindersAccess: String?
    public var eventsAccess: String?

    public init(
        version: String = ProductConstants.version,
        schemaVersion: Int = 2,
        cloudKitMode: String,
        cloudKitAccount: String = "unknown",
        entities: [String] = ["events", "tasks", "missions", "habits"],
        sqlite: Bool = true,
        mcp: Bool = true,
        broker: Bool = true,
        remindersAccess: String? = nil,
        eventsAccess: String? = nil
    ) {
        self.version = version
        self.schemaVersion = schemaVersion
        self.cloudKitMode = cloudKitMode
        self.cloudKitAccount = cloudKitAccount
        self.entities = entities
        self.sqlite = sqlite
        self.mcp = mcp
        self.broker = broker
        self.remindersAccess = remindersAccess
        self.eventsAccess = eventsAccess
    }
}

public struct SystemDoctorReport: Equatable, Codable, Sendable {
    public var version: String
    public var schemaVersion: Int
    public var sqlitePath: String?
    public var sqliteIntegrity: String
    public var sqliteError: String?
    public var cloudMode: String
    public var cloudKitAccount: String
    public var cloudKitZone: String
    public var cloudOutbox: Int
    public var lastFetchAt: Date?
    public var lastSendAt: Date?
    public var openConflicts: Int
    public var pendingSaga: Int
    public var cloudInbox: Int
    public var remindersAccess: String
    public var eventsAccess: String
    public var projectionDrift: Int
    public var brokerListening: Bool

    public init(
        version: String = ProductConstants.version,
        schemaVersion: Int = 2,
        sqlitePath: String? = nil,
        sqliteIntegrity: String,
        sqliteError: String? = nil,
        cloudMode: String,
        cloudKitAccount: String,
        cloudKitZone: String = CloudKitSchema.zoneName,
        cloudOutbox: Int,
        lastFetchAt: Date? = nil,
        lastSendAt: Date? = nil,
        openConflicts: Int = 0,
        pendingSaga: Int = 0,
        cloudInbox: Int = 0,
        remindersAccess: String,
        eventsAccess: String,
        projectionDrift: Int = 0,
        brokerListening: Bool
    ) {
        self.version = version
        self.schemaVersion = schemaVersion
        self.sqlitePath = sqlitePath
        self.sqliteIntegrity = sqliteIntegrity
        self.sqliteError = sqliteError
        self.cloudMode = cloudMode
        self.cloudKitAccount = cloudKitAccount
        self.cloudKitZone = cloudKitZone
        self.cloudOutbox = cloudOutbox
        self.lastFetchAt = lastFetchAt
        self.lastSendAt = lastSendAt
        self.openConflicts = openConflicts
        self.pendingSaga = pendingSaga
        self.cloudInbox = cloudInbox
        self.remindersAccess = remindersAccess
        self.eventsAccess = eventsAccess
        self.projectionDrift = projectionDrift
        self.brokerListening = brokerListening
    }
}

public struct IDParams: Equatable, Codable, Sendable {
    public var id: UUID
    public var confirmID: UUID?
    public var permanent: Bool?
    public var value: Decimal?
    public var at: Date?
    public var fillToTarget: Bool?
    public var note: String?
    public var periodKey: String?
    public var missionID: UUID?
    public var seriesID: UUID?
    public var scope: EditScope?
    public var ack: Bool?

    public init(
        id: UUID,
        confirmID: UUID? = nil,
        permanent: Bool? = nil,
        value: Decimal? = nil,
        at: Date? = nil,
        fillToTarget: Bool? = nil,
        note: String? = nil,
        periodKey: String? = nil,
        missionID: UUID? = nil,
        seriesID: UUID? = nil,
        scope: EditScope? = nil,
        ack: Bool? = nil
    ) {
        self.id = id
        self.confirmID = confirmID
        self.permanent = permanent
        self.value = value
        self.at = at
        self.fillToTarget = fillToTarget
        self.note = note
        self.periodKey = periodKey
        self.missionID = missionID
        self.seriesID = seriesID
        self.scope = scope
        self.ack = ack
    }
}

public struct CloudModeParams: Equatable, Codable, Sendable {
    public var mode: CloudSyncMode

    public init(mode: CloudSyncMode) {
        self.mode = mode
    }
}

public struct ProjectionSettingsParams: Equatable, Codable, Sendable {
    public var projectTasks: Bool?
    public var projectHabits: Bool?
    public var projectMissions: Bool?
    public var acceptNativeCompletion: Bool?

    public init(
        projectTasks: Bool? = nil,
        projectHabits: Bool? = nil,
        projectMissions: Bool? = nil,
        acceptNativeCompletion: Bool? = nil
    ) {
        self.projectTasks = projectTasks
        self.projectHabits = projectHabits
        self.projectMissions = projectMissions
        self.acceptNativeCompletion = acceptNativeCompletion
    }
}

public struct TaskUpdateParams: Equatable, Codable, Sendable {
    public var id: UUID
    public var patch: PatchTaskCommand

    public init(id: UUID, patch: PatchTaskCommand) {
        self.id = id
        self.patch = patch
    }
}

public struct MissionUpdateParams: Equatable, Codable, Sendable {
    public var id: UUID
    public var patch: PatchMissionCommand

    public init(id: UUID, patch: PatchMissionCommand) {
        self.id = id
        self.patch = patch
    }
}

public struct HabitUpdateParams: Equatable, Codable, Sendable {
    public var id: UUID
    public var patch: PatchHabitCommand

    public init(id: UUID, patch: PatchHabitCommand) {
        self.id = id
        self.patch = patch
    }
}

public struct MissionTaskParams: Equatable, Codable, Sendable {
    public var missionID: UUID
    public var seriesID: UUID

    public init(missionID: UUID, seriesID: UUID) {
        self.missionID = missionID
        self.seriesID = seriesID
    }
}

public struct CreateHabitCommand: Equatable, Codable, Sendable {
    public var title: String
    public var markdownDescription: String?
    public var metric: HabitMetric
    public var targetValue: Decimal
    public var unit: String?
    public var schedule: HabitSchedule
    public var activeFrom: LocalDate
    public var activeUntil: LocalDate?
    public var reminderTimes: [String]
    public var allowBackfillDays: Int
    public var completionPolicy: HabitCompletionPolicy
    public var projectionPolicy: ProjectionPolicy
    public var missionID: UUID?

    public init(
        title: String,
        markdownDescription: String? = nil,
        metric: HabitMetric,
        targetValue: Decimal = 1,
        unit: String? = nil,
        schedule: HabitSchedule = .daily,
        activeFrom: LocalDate,
        activeUntil: LocalDate? = nil,
        reminderTimes: [String] = [],
        allowBackfillDays: Int = 1,
        completionPolicy: HabitCompletionPolicy = .reachTarget,
        projectionPolicy: ProjectionPolicy = .none,
        missionID: UUID? = nil
    ) {
        self.title = title
        self.markdownDescription = markdownDescription
        self.metric = metric
        self.targetValue = targetValue
        self.unit = unit
        self.schedule = schedule
        self.activeFrom = activeFrom
        self.activeUntil = activeUntil
        self.reminderTimes = reminderTimes
        self.allowBackfillDays = allowBackfillDays
        self.completionPolicy = completionPolicy
        self.projectionPolicy = projectionPolicy
        self.missionID = missionID
    }
}

public struct CursorPage<T: Codable & Sendable>: Codable, Sendable {
    public var items: [T]
    public var nextCursor: String?

    public init(items: [T], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct TaskListFilter: Equatable, Codable, Sendable {
    public var query: String?
    public var missionID: UUID?
    public var inboxOnly: Bool
    public var openOnly: Bool
    public var completedOnly: Bool
    public var overdueOnly: Bool
    public var limit: Int
    public var cursor: String?

    public init(
        query: String? = nil,
        missionID: UUID? = nil,
        inboxOnly: Bool = false,
        openOnly: Bool = false,
        completedOnly: Bool = false,
        overdueOnly: Bool = false,
        limit: Int = 50,
        cursor: String? = nil
    ) {
        self.query = query
        self.missionID = missionID
        self.inboxOnly = inboxOnly
        self.openOnly = openOnly
        self.completedOnly = completedOnly
        self.overdueOnly = overdueOnly
        self.limit = limit
        self.cursor = cursor
    }
}
