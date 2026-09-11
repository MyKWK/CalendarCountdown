import CalendarCountdownCore
import Foundation
import GRDB

struct MissionRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "missions"

    var id: String
    var title: String
    var descriptionMd: String?
    var color: String
    var icon: String
    var status: String
    var targetDate: String?
    var defaultWorkload: Int
    var sortKey: String
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, color, icon, status, revision
        case descriptionMd = "description_md"
        case targetDate = "target_date"
        case defaultWorkload = "default_workload"
        case sortKey = "sort_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ mission: MissionDefinition) {
        id = SQLValue.uuid(mission.id)
        title = mission.title
        descriptionMd = mission.markdownDescription
        color = mission.color
        icon = mission.icon
        status = mission.status.rawValue
        targetDate = mission.targetDate?.isoString
        defaultWorkload = mission.defaultWorkload.rawValue
        sortKey = mission.sortKey
        createdAt = RFC3339.utcString(from: mission.createdAt)
        updatedAt = RFC3339.utcString(from: mission.updatedAt)
        revision = mission.revision
        modifiedByDevice = SQLValue.uuid(mission.modifiedByDevice)
        deletedAt = SQLValue.date(mission.deletedAt)
    }

    func domain() throws -> MissionDefinition {
        MissionDefinition(
            id: try SQLValue.uuid(id),
            title: title,
            markdownDescription: descriptionMd,
            color: color,
            icon: icon,
            status: MissionStatus(rawValue: status) ?? .active,
            targetDate: targetDate.flatMap(LocalDate.parse),
            defaultWorkload: WorkloadPoints(rawValue: defaultWorkload) ?? .one,
            sortKey: sortKey,
            createdAt: try SQLValue.requiredDate(createdAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct TaskSeriesRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "task_series"

    var id: String
    var title: String
    var descriptionMd: String?
    var kind: String
    var missionId: String?
    var priority: String
    var recurrenceMode: String?
    var rrule: String?
    var recurrenceEndKind: String?
    var recurrenceEndValue: String?
    var recurrenceJson: String?
    var workload: Int
    var timeZone: String
    var invalidDatePolicy: String?
    var projectionPolicy: String
    var isAllDay: Int
    var firstPlannedStart: String?
    var firstPlannedDue: String?
    var alertsJson: String?
    var sortKey: String
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, priority, rrule, workload, revision
        case descriptionMd = "description_md"
        case missionId = "mission_id"
        case recurrenceMode = "recurrence_mode"
        case recurrenceEndKind = "recurrence_end_kind"
        case recurrenceEndValue = "recurrence_end_value"
        case recurrenceJson = "recurrence_json"
        case timeZone = "time_zone"
        case invalidDatePolicy = "invalid_date_policy"
        case projectionPolicy = "projection_policy"
        case isAllDay = "is_all_day"
        case firstPlannedStart = "first_planned_start"
        case firstPlannedDue = "first_planned_due"
        case alertsJson = "alerts_json"
        case sortKey = "sort_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ series: TaskSeries) throws {
        id = SQLValue.uuid(series.id)
        title = series.title
        descriptionMd = series.markdownDescription
        kind = series.kind.rawValue
        missionId = series.missionID.map(SQLValue.uuid)
        priority = series.priority.rawValue
        recurrenceMode = series.recurrence?.mode.rawValue
        rrule = series.recurrence.map(RecurrenceRuleCodec.rrule(from:))
        switch series.recurrence?.end {
        case .never:
            recurrenceEndKind = "never"
            recurrenceEndValue = nil
        case let .afterOccurrences(count):
            recurrenceEndKind = "afterOccurrences"
            recurrenceEndValue = String(count)
        case let .onDate(date):
            recurrenceEndKind = "onDate"
            recurrenceEndValue = date.isoString
        case nil:
            recurrenceEndKind = nil
            recurrenceEndValue = nil
        }
        recurrenceJson = try series.recurrence.map(SQLValue.json)
        workload = series.workload.rawValue
        timeZone = series.schedule.timeZoneIdentifier
        invalidDatePolicy = series.recurrence?.invalidDatePolicy.rawValue
        projectionPolicy = series.projectionPolicy.rawValue
        isAllDay = series.schedule.isAllDay ? 1 : 0
        firstPlannedStart = SQLValue.date(series.schedule.plannedStart)
        firstPlannedDue = SQLValue.date(series.schedule.plannedDue)
        alertsJson = try SQLValue.json(series.alerts)
        sortKey = series.sortKey
        createdAt = RFC3339.utcString(from: series.createdAt)
        updatedAt = RFC3339.utcString(from: series.updatedAt)
        revision = series.revision
        modifiedByDevice = SQLValue.uuid(series.modifiedByDevice)
        deletedAt = SQLValue.date(series.deletedAt)
    }

    func domain() throws -> TaskSeries {
        let recurrence = try SQLValue.json(RecurrenceSpec.self, recurrenceJson)
        return TaskSeries(
            id: try SQLValue.uuid(id),
            title: title,
            markdownDescription: descriptionMd,
            kind: TaskKind(rawValue: kind) ?? .deadline,
            missionID: try missionId.map(SQLValue.uuid),
            priority: TaskPriority(rawValue: priority) ?? .none,
            workload: WorkloadPoints(rawValue: workload) ?? .one,
            schedule: TaskSchedule(
                timeZoneIdentifier: timeZone,
                isAllDay: isAllDay != 0,
                plannedStart: try SQLValue.date(firstPlannedStart),
                plannedDue: try SQLValue.date(firstPlannedDue)
            ),
            recurrence: recurrence,
            alerts: try SQLValue.json([AlertSpec].self, alertsJson) ?? [],
            projectionPolicy: ProjectionPolicy(rawValue: projectionPolicy) ?? .none,
            sortKey: sortKey,
            createdAt: try SQLValue.requiredDate(createdAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct TaskOccurrenceRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "task_occurrences"

    var id: String
    var seriesId: String
    var occurrenceKey: String
    var titleOverride: String?
    var descriptionOverrideMd: String?
    var plannedStart: String?
    var plannedDue: String?
    var status: String
    var completedAt: String?
    var disposition: String
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, revision, disposition
        case seriesId = "series_id"
        case occurrenceKey = "occurrence_key"
        case titleOverride = "title_override"
        case descriptionOverrideMd = "description_override_md"
        case plannedStart = "planned_start"
        case plannedDue = "planned_due"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ occurrence: TaskOccurrence) {
        id = SQLValue.uuid(occurrence.id)
        seriesId = SQLValue.uuid(occurrence.seriesID)
        occurrenceKey = occurrence.occurrenceKey
        titleOverride = occurrence.titleOverride
        descriptionOverrideMd = occurrence.descriptionOverrideMarkdown
        plannedStart = SQLValue.date(occurrence.plannedStart)
        plannedDue = SQLValue.date(occurrence.plannedDue)
        status = occurrence.status.rawValue
        completedAt = SQLValue.date(occurrence.completedAt)
        disposition = occurrence.disposition.rawValue
        createdAt = RFC3339.utcString(from: occurrence.createdAt)
        updatedAt = RFC3339.utcString(from: occurrence.updatedAt)
        revision = occurrence.revision
        modifiedByDevice = SQLValue.uuid(occurrence.modifiedByDevice)
        deletedAt = SQLValue.date(occurrence.deletedAt)
    }

    func domain() throws -> TaskOccurrence {
        TaskOccurrence(
            id: try SQLValue.uuid(id),
            seriesID: try SQLValue.uuid(seriesId),
            occurrenceKey: occurrenceKey,
            titleOverride: titleOverride,
            descriptionOverrideMarkdown: descriptionOverrideMd,
            plannedStart: try SQLValue.date(plannedStart),
            plannedDue: try SQLValue.date(plannedDue),
            status: TaskOccurrenceStatus(rawValue: status) ?? .open,
            completedAt: try SQLValue.date(completedAt),
            disposition: OccurrenceDisposition(rawValue: disposition) ?? .planned,
            createdAt: try SQLValue.requiredDate(createdAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct HabitRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "habits"

    var id: String
    var title: String
    var descriptionMd: String?
    var metric: String
    var targetValue: String
    var unit: String?
    var scheduleRule: String
    var activeFrom: String
    var activeUntil: String?
    var reminderTimesJson: String?
    var allowBackfillDays: Int
    var completionPolicy: String
    var projectionPolicy: String
    var missionId: String?
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, metric, unit, revision
        case descriptionMd = "description_md"
        case targetValue = "target_value"
        case scheduleRule = "schedule_rule"
        case activeFrom = "active_from"
        case activeUntil = "active_until"
        case reminderTimesJson = "reminder_times_json"
        case allowBackfillDays = "allow_backfill_days"
        case completionPolicy = "completion_policy"
        case projectionPolicy = "projection_policy"
        case missionId = "mission_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ habit: HabitDefinition) throws {
        id = SQLValue.uuid(habit.id)
        title = habit.title
        descriptionMd = habit.markdownDescription
        metric = habit.metric.rawValue
        targetValue = SQLValue.decimal(habit.targetValue)
        unit = habit.unit
        scheduleRule = try SQLValue.json(habit.schedule)
        activeFrom = habit.activeFrom.isoString
        activeUntil = habit.activeUntil?.isoString
        reminderTimesJson = try SQLValue.json(habit.reminderTimes)
        allowBackfillDays = habit.allowBackfillDays
        completionPolicy = habit.completionPolicy.rawValue
        projectionPolicy = habit.projectionPolicy.rawValue
        missionId = habit.missionID.map(SQLValue.uuid)
        createdAt = RFC3339.utcString(from: habit.createdAt)
        updatedAt = RFC3339.utcString(from: habit.updatedAt)
        revision = habit.revision
        modifiedByDevice = SQLValue.uuid(habit.modifiedByDevice)
        deletedAt = SQLValue.date(habit.deletedAt)
    }

    func domain() throws -> HabitDefinition {
        HabitDefinition(
            id: try SQLValue.uuid(id),
            title: title,
            markdownDescription: descriptionMd,
            metric: HabitMetric(rawValue: metric) ?? .binary,
            targetValue: try SQLValue.decimal(targetValue),
            unit: unit,
            schedule: try SQLValue.json(HabitSchedule.self, scheduleRule) ?? .daily,
            activeFrom: LocalDate.parse(activeFrom) ?? LocalDate(year: 1970, month: 1, day: 1),
            activeUntil: activeUntil.flatMap(LocalDate.parse),
            reminderTimes: try SQLValue.json([String].self, reminderTimesJson) ?? [],
            allowBackfillDays: allowBackfillDays,
            completionPolicy: HabitCompletionPolicy(rawValue: completionPolicy) ?? .reachTarget,
            projectionPolicy: ProjectionPolicy(rawValue: projectionPolicy) ?? .none,
            missionID: try missionId.map(SQLValue.uuid),
            createdAt: try SQLValue.requiredDate(createdAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct HabitPeriodRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "habit_periods"

    var habitId: String
    var periodKey: String
    var targetValueSnapshot: String
    var disposition: String
    var completedAt: String?
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case disposition, revision
        case habitId = "habit_id"
        case periodKey = "period_key"
        case targetValueSnapshot = "target_value_snapshot"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ period: HabitPeriod) {
        habitId = SQLValue.uuid(period.habitID)
        periodKey = period.periodKey
        targetValueSnapshot = SQLValue.decimal(period.targetValueSnapshot)
        disposition = period.disposition.rawValue
        completedAt = SQLValue.date(period.completedAt)
        updatedAt = RFC3339.utcString(from: period.updatedAt)
        revision = period.revision
        modifiedByDevice = SQLValue.uuid(period.modifiedByDevice)
        deletedAt = SQLValue.date(period.deletedAt)
    }

    func domain() throws -> HabitPeriod {
        HabitPeriod(
            habitID: try SQLValue.uuid(habitId),
            periodKey: periodKey,
            targetValueSnapshot: try SQLValue.decimal(targetValueSnapshot),
            disposition: HabitPeriodDisposition(rawValue: disposition) ?? .open,
            completedAt: try SQLValue.date(completedAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct CheckInRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "checkins"

    var id: String
    var habitId: String
    var periodKey: String
    var value: String
    var unit: String?
    var effectiveAt: String
    var recordedAt: String
    var source: String
    var note: String?
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, value, unit, source, note, revision
        case habitId = "habit_id"
        case periodKey = "period_key"
        case effectiveAt = "effective_at"
        case recordedAt = "recorded_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ record: CheckInRecord) {
        id = SQLValue.uuid(record.id)
        habitId = SQLValue.uuid(record.habitID)
        periodKey = record.periodKey
        value = SQLValue.decimal(record.value)
        unit = record.unit
        effectiveAt = RFC3339.utcString(from: record.effectiveAt)
        recordedAt = RFC3339.utcString(from: record.recordedAt)
        source = record.source.rawValue
        note = record.note
        createdAt = RFC3339.utcString(from: record.createdAt)
        updatedAt = RFC3339.utcString(from: record.updatedAt)
        revision = record.revision
        modifiedByDevice = SQLValue.uuid(record.modifiedByDevice)
        deletedAt = SQLValue.date(record.deletedAt)
    }

    func domain() throws -> CheckInRecord {
        CheckInRecord(
            id: try SQLValue.uuid(id),
            habitID: try SQLValue.uuid(habitId),
            periodKey: periodKey,
            value: try SQLValue.decimal(value),
            unit: unit,
            effectiveAt: try SQLValue.requiredDate(effectiveAt),
            recordedAt: try SQLValue.requiredDate(recordedAt),
            source: CheckInSource(rawValue: source) ?? .app,
            note: note,
            createdAt: try SQLValue.requiredDate(createdAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct ProjectionSettingsRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "projection_settings"

    var id: String
    var projectTasks: Int
    var projectHabits: Int
    var projectMissions: Int
    var acceptNativeCompletion: Int
    var acceptNativeScheduleChanges: Int
    var revision: Int64
    var updatedAt: String
    var modifiedByDevice: String

    enum CodingKeys: String, CodingKey {
        case id, revision
        case projectTasks = "project_tasks"
        case projectHabits = "project_habits"
        case projectMissions = "project_missions"
        case acceptNativeCompletion = "accept_native_completion"
        case acceptNativeScheduleChanges = "accept_native_schedule_changes"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
    }

    init(_ settings: ProjectionSettings) {
        id = SQLValue.uuid(settings.id)
        projectTasks = settings.projectTasks ? 1 : 0
        projectHabits = settings.projectHabits ? 1 : 0
        projectMissions = settings.projectMissions ? 1 : 0
        acceptNativeCompletion = settings.acceptNativeCompletion ? 1 : 0
        acceptNativeScheduleChanges = settings.acceptNativeScheduleChanges ? 1 : 0
        revision = settings.revision
        updatedAt = RFC3339.utcString(from: settings.updatedAt)
        modifiedByDevice = SQLValue.uuid(settings.modifiedByDevice)
    }

    func domain() throws -> ProjectionSettings {
        ProjectionSettings(
            id: try SQLValue.uuid(id),
            projectTasks: projectTasks != 0,
            projectHabits: projectHabits != 0,
            projectMissions: projectMissions != 0,
            acceptNativeCompletion: acceptNativeCompletion != 0,
            acceptNativeScheduleChanges: acceptNativeScheduleChanges != 0,
            revision: revision,
            updatedAt: try SQLValue.requiredDate(updatedAt),
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice)
        )
    }
}

struct IdempotencyRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "idempotency_keys"

    var key: String
    var commandName: String
    var requestHash: String
    var responseJson: String
    var createdAt: String
    var expiresAt: String

    enum CodingKeys: String, CodingKey {
        case key
        case commandName = "command_name"
        case requestHash = "request_hash"
        case responseJson = "response_json"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct CloudOutboxRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "cloud_outbox"

    var id: String
    var recordType: String
    var recordName: String
    var operation: String
    var localRevision: Int64
    var enqueuedAt: String
    var retryCount: Int
    var lastErrorCode: String?
    var payloadJson: String?
    var fieldsJson: String?
    var modifiedByDevice: String?
    var updatedAt: String?
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, operation
        case recordType = "record_type"
        case recordName = "record_name"
        case localRevision = "local_revision"
        case enqueuedAt = "enqueued_at"
        case retryCount = "retry_count"
        case lastErrorCode = "last_error_code"
        case payloadJson = "payload_json"
        case fieldsJson = "fields_json"
        case modifiedByDevice = "modified_by_device"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct CloudInboxRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "cloud_inbox"

    var id: String
    var recordType: String
    var recordName: String
    var operation: String
    var revision: Int64
    var payloadJson: String
    var fieldsJson: String?
    var modifiedByDevice: String
    var updatedAt: String
    var deletedAt: String?
    var receivedAt: String
    var retryCount: Int
    var lastError: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id, operation, revision, status
        case recordType = "record_type"
        case recordName = "record_name"
        case payloadJson = "payload_json"
        case fieldsJson = "fields_json"
        case modifiedByDevice = "modified_by_device"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case receivedAt = "received_at"
        case retryCount = "retry_count"
        case lastError = "last_error"
    }
}

struct FieldAncestorRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "field_ancestors"

    var objectType: String
    var objectId: String
    var fieldName: String
    var value: String?
    var hlc: String

    enum CodingKeys: String, CodingKey {
        case value, hlc
        case objectType = "object_type"
        case objectId = "object_id"
        case fieldName = "field_name"
    }
}

struct CloudSyncStateRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "cloud_sync_state"

    var scope: String
    var ckStateSerialization: Data?
    var accountIdentifierHash: String?
    var lastFetchAt: String?
    var lastSendAt: String?

    enum CodingKeys: String, CodingKey {
        case scope
        case ckStateSerialization = "ck_state_serialization"
        case accountIdentifierHash = "account_identifier_hash"
        case lastFetchAt = "last_fetch_at"
        case lastSendAt = "last_send_at"
    }
}

struct OperationJournalRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "operation_journal"

    var requestId: String
    var actor: String
    var command: String
    var objectType: String
    var objectId: String
    var beforeRevision: Int64?
    var afterRevision: Int64?
    var effectSummary: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case actor, command
        case requestId = "request_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case beforeRevision = "before_revision"
        case afterRevision = "after_revision"
        case effectSummary = "effect_summary"
        case createdAt = "created_at"
    }
}

struct FieldVersionRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "field_versions"

    var objectType: String
    var objectId: String
    var fieldName: String
    var hlc: String
    var modifiedByDevice: String

    enum CodingKeys: String, CodingKey {
        case hlc
        case objectType = "object_type"
        case objectId = "object_id"
        case fieldName = "field_name"
        case modifiedByDevice = "modified_by_device"
    }
}

struct MergeConflictRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "merge_conflicts"

    var id: String
    var objectType: String
    var objectId: String
    var fieldName: String
    var localValue: String?
    var remoteValue: String?
    var ancestorValue: String?
    var detectedAt: String
    var resolution: String?
    var resolvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, resolution
        case objectType = "object_type"
        case objectId = "object_id"
        case fieldName = "field_name"
        case localValue = "local_value"
        case remoteValue = "remote_value"
        case ancestorValue = "ancestor_value"
        case detectedAt = "detected_at"
        case resolvedAt = "resolved_at"
    }
}

struct ProjectionBindingRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "projection_bindings"

    var domainType: String
    var domainId: String
    var projectionKind: String
    var appleIdentifier: String?
    var appleExternalIdentifier: String?
    var desiredRevision: Int64
    var projectedRevision: Int64?
    var fingerprint: String?
    var lastSeenAt: String?
    var state: String
    var errorCode: String?

    enum CodingKeys: String, CodingKey {
        case fingerprint, state
        case domainType = "domain_type"
        case domainId = "domain_id"
        case projectionKind = "projection_kind"
        case appleIdentifier = "apple_identifier"
        case appleExternalIdentifier = "apple_external_identifier"
        case desiredRevision = "desired_revision"
        case projectedRevision = "projected_revision"
        case lastSeenAt = "last_seen_at"
        case errorCode = "error_code"
    }
}

struct PendingOperationRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "pending_operations"

    var id: String
    var requestId: String
    var command: String
    var objectType: String
    var objectId: String
    var stage: String
    var startedAt: String
    var updatedAt: String
    var retryCount: Int
    var lastErrorCode: String?

    enum CodingKeys: String, CodingKey {
        case id, command, stage
        case requestId = "request_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case retryCount = "retry_count"
        case lastErrorCode = "last_error_code"
    }
}

struct ManagedEventRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "managed_events"

    var id: String
    var externalId: String?
    var title: String
    var calendarTitle: String?
    var calendarIdentifier: String?
    var calendarSystem: String
    var recurrence: String
    var date: String?
    var time: String?
    var startYear: Int?
    var lunarMonth: Int?
    var lunarDay: Int?
    var lunarLeapMonthPolicy: String
    var invalidLunarDayPolicy: String
    var isAllDay: Int
    var alertDaysJson: String
    var notes: String?
    var selectForCountdown: Int
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, date, time, notes, revision
        case externalId = "external_id"
        case calendarTitle = "calendar_title"
        case calendarIdentifier = "calendar_identifier"
        case calendarSystem = "calendar_system"
        case recurrence
        case startYear = "start_year"
        case lunarMonth = "lunar_month"
        case lunarDay = "lunar_day"
        case lunarLeapMonthPolicy = "lunar_leap_month_policy"
        case invalidLunarDayPolicy = "invalid_lunar_day_policy"
        case isAllDay = "is_all_day"
        case alertDaysJson = "alert_days_json"
        case selectForCountdown = "select_for_countdown"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ record: ManagedEventRecord) throws {
        id = SQLValue.uuid(record.id)
        externalId = record.draft.externalId
        title = record.draft.title
        calendarTitle = record.draft.calendarTitle
        calendarIdentifier = record.draft.calendarIdentifier
        calendarSystem = record.draft.calendarSystem.rawValue
        recurrence = record.draft.recurrence.rawValue
        date = record.draft.date
        time = record.draft.time
        startYear = record.draft.startYear
        lunarMonth = record.draft.lunarMonth
        lunarDay = record.draft.lunarDay
        lunarLeapMonthPolicy = record.draft.lunarLeapMonthPolicy.rawValue
        invalidLunarDayPolicy = record.draft.invalidLunarDayPolicy.rawValue
        isAllDay = record.draft.isAllDay ? 1 : 0
        alertDaysJson = try SQLValue.json(record.draft.alertDaysBefore)
        notes = record.draft.notes
        selectForCountdown = record.draft.selectForCountdown ? 1 : 0
        createdAt = RFC3339.utcString(from: record.createdAt)
        updatedAt = RFC3339.utcString(from: record.updatedAt)
        revision = record.revision
        modifiedByDevice = SQLValue.uuid(record.modifiedByDevice)
        deletedAt = SQLValue.date(record.deletedAt)
    }

    func domain() throws -> ManagedEventRecord {
        ManagedEventRecord(
            id: try SQLValue.uuid(id),
            draft: ManagedEventDraft(
                externalId: externalId,
                title: title,
                calendarTitle: calendarTitle,
                calendarIdentifier: calendarIdentifier,
                calendarSystem: CalendarSystemKind(rawValue: calendarSystem) ?? .gregorian,
                recurrence: RecurrenceKind(rawValue: recurrence) ?? .none,
                date: date,
                time: time,
                startYear: startYear,
                lunarMonth: lunarMonth,
                lunarDay: lunarDay,
                lunarLeapMonthPolicy: LunarLeapMonthPolicy(rawValue: lunarLeapMonthPolicy) ?? .regularOnly,
                invalidLunarDayPolicy: InvalidLunarDayPolicy(rawValue: invalidLunarDayPolicy) ?? .clampToMonthEnd,
                isAllDay: isAllDay != 0,
                alertDaysBefore: try SQLValue.json([Int].self, alertDaysJson) ?? [],
                notes: notes,
                selectForCountdown: selectForCountdown != 0
            ),
            createdAt: try SQLValue.requiredDate(createdAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct CountdownSelectionRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "countdown_selections"

    var id: String
    var mode: String
    var calendarIdentifier: String?
    var calendarTitle: String
    var eventIdentifier: String?
    var externalIdentifier: String?
    var managedRecordId: String?
    var eventTitle: String
    var occurrenceDate: String?
    var selectedAt: String
    var updatedAt: String
    var revision: Int64
    var modifiedByDevice: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, mode, revision
        case calendarIdentifier = "calendar_identifier"
        case calendarTitle = "calendar_title"
        case eventIdentifier = "event_identifier"
        case externalIdentifier = "external_identifier"
        case managedRecordId = "managed_record_id"
        case eventTitle = "event_title"
        case occurrenceDate = "occurrence_date"
        case selectedAt = "selected_at"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    init(_ selection: CountdownSelection) {
        id = SQLValue.uuid(selection.id)
        mode = selection.mode.rawValue
        calendarIdentifier = selection.calendarIdentifier
        calendarTitle = selection.calendarTitle
        eventIdentifier = selection.eventIdentifier
        externalIdentifier = selection.externalIdentifier
        managedRecordId = selection.managedRecordID.map(SQLValue.uuid)
        eventTitle = selection.eventTitle
        occurrenceDate = SQLValue.date(selection.occurrenceDate)
        selectedAt = RFC3339.utcString(from: selection.selectedAt)
        updatedAt = RFC3339.utcString(from: selection.updatedAt)
        revision = selection.revision
        modifiedByDevice = SQLValue.uuid(selection.modifiedByDevice)
        deletedAt = SQLValue.date(selection.deletedAt)
    }

    func domain() throws -> CountdownSelection {
        CountdownSelection(
            id: try SQLValue.uuid(id),
            mode: SelectionMode(rawValue: mode) ?? .annualTitle,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: calendarTitle,
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            managedRecordID: try managedRecordId.map(SQLValue.uuid),
            eventTitle: eventTitle,
            occurrenceDate: try SQLValue.date(occurrenceDate),
            selectedAt: try SQLValue.requiredDate(selectedAt),
            updatedAt: try SQLValue.requiredDate(updatedAt),
            revision: revision,
            modifiedByDevice: try SQLValue.uuid(modifiedByDevice),
            deletedAt: try SQLValue.date(deletedAt)
        )
    }
}

struct CountdownPreferencesRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "countdown_preferences"

    var id: String
    var pinnedSelectionId: String?
    var revision: Int64
    var updatedAt: String
    var modifiedByDevice: String

    enum CodingKeys: String, CodingKey {
        case id, revision
        case pinnedSelectionId = "pinned_selection_id"
        case updatedAt = "updated_at"
        case modifiedByDevice = "modified_by_device"
    }
}

struct CountdownHiddenCalendarRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "countdown_hidden_calendars"

    var calendarIdentifier: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case calendarIdentifier = "calendar_identifier"
        case updatedAt = "updated_at"
    }
}
