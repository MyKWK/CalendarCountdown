import CalendarCountdownCore
import Foundation
import GRDB

enum DatabaseMigrations {
    static func make() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE local_kv (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );

                CREATE TABLE missions (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    description_md TEXT,
                    color TEXT NOT NULL,
                    icon TEXT NOT NULL,
                    status TEXT NOT NULL,
                    target_date TEXT,
                    default_workload INTEGER NOT NULL,
                    sort_key TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT
                );

                CREATE TABLE task_series (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    description_md TEXT,
                    kind TEXT NOT NULL,
                    mission_id TEXT,
                    priority TEXT NOT NULL,
                    recurrence_mode TEXT,
                    rrule TEXT,
                    recurrence_end_kind TEXT,
                    recurrence_end_value TEXT,
                    recurrence_json TEXT,
                    workload INTEGER NOT NULL,
                    time_zone TEXT NOT NULL,
                    invalid_date_policy TEXT,
                    projection_policy TEXT NOT NULL,
                    is_all_day INTEGER NOT NULL DEFAULT 0,
                    first_planned_start TEXT,
                    first_planned_due TEXT,
                    alerts_json TEXT,
                    sort_key TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT,
                    FOREIGN KEY(mission_id) REFERENCES missions(id) ON DELETE SET NULL ON UPDATE CASCADE
                );

                CREATE TABLE task_occurrences (
                    id TEXT PRIMARY KEY NOT NULL,
                    series_id TEXT NOT NULL,
                    occurrence_key TEXT NOT NULL UNIQUE,
                    title_override TEXT,
                    description_override_md TEXT,
                    planned_start TEXT,
                    planned_due TEXT,
                    status TEXT NOT NULL,
                    completed_at TEXT,
                    disposition TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT,
                    FOREIGN KEY(series_id) REFERENCES task_series(id) ON DELETE RESTRICT ON UPDATE CASCADE
                );

                CREATE TABLE habits (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    description_md TEXT,
                    metric TEXT NOT NULL,
                    target_value TEXT NOT NULL,
                    unit TEXT,
                    schedule_rule TEXT NOT NULL,
                    active_from TEXT NOT NULL,
                    active_until TEXT,
                    reminder_times_json TEXT,
                    allow_backfill_days INTEGER NOT NULL,
                    completion_policy TEXT NOT NULL,
                    projection_policy TEXT NOT NULL,
                    mission_id TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT,
                    FOREIGN KEY(mission_id) REFERENCES missions(id) ON DELETE SET NULL ON UPDATE CASCADE
                );

                CREATE TABLE habit_periods (
                    habit_id TEXT NOT NULL,
                    period_key TEXT NOT NULL,
                    target_value_snapshot TEXT NOT NULL,
                    disposition TEXT NOT NULL,
                    completed_at TEXT,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT,
                    PRIMARY KEY (habit_id, period_key),
                    FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE RESTRICT ON UPDATE CASCADE
                );

                CREATE TABLE checkins (
                    id TEXT PRIMARY KEY NOT NULL,
                    habit_id TEXT NOT NULL,
                    period_key TEXT NOT NULL,
                    value TEXT NOT NULL,
                    unit TEXT,
                    effective_at TEXT NOT NULL,
                    recorded_at TEXT NOT NULL,
                    source TEXT NOT NULL,
                    note TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT,
                    FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE RESTRICT ON UPDATE CASCADE
                );

                CREATE TABLE projection_bindings (
                    domain_type TEXT NOT NULL,
                    domain_id TEXT NOT NULL,
                    projection_kind TEXT NOT NULL,
                    apple_identifier TEXT,
                    apple_external_identifier TEXT,
                    desired_revision INTEGER NOT NULL,
                    projected_revision INTEGER,
                    fingerprint TEXT,
                    last_seen_at TEXT,
                    state TEXT NOT NULL,
                    error_code TEXT,
                    PRIMARY KEY (domain_type, domain_id, projection_kind)
                );

                CREATE TABLE projection_settings (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_tasks INTEGER NOT NULL,
                    project_habits INTEGER NOT NULL,
                    project_missions INTEGER NOT NULL,
                    accept_native_completion INTEGER NOT NULL,
                    accept_native_schedule_changes INTEGER NOT NULL,
                    revision INTEGER NOT NULL,
                    updated_at TEXT NOT NULL,
                    modified_by_device TEXT NOT NULL
                );

                CREATE TABLE projection_destinations (
                    projection_kind TEXT PRIMARY KEY NOT NULL,
                    apple_calendar_identifier TEXT,
                    apple_calendar_title TEXT,
                    apple_source_identifier TEXT,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE idempotency_keys (
                    key TEXT PRIMARY KEY NOT NULL,
                    command_name TEXT NOT NULL,
                    request_hash TEXT NOT NULL,
                    response_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL
                );

                CREATE TABLE cloud_outbox (
                    id TEXT PRIMARY KEY NOT NULL,
                    record_type TEXT NOT NULL,
                    record_name TEXT NOT NULL,
                    operation TEXT NOT NULL,
                    local_revision INTEGER NOT NULL,
                    enqueued_at TEXT NOT NULL,
                    retry_count INTEGER NOT NULL DEFAULT 0,
                    last_error_code TEXT
                );

                CREATE TABLE cloud_sync_state (
                    scope TEXT PRIMARY KEY NOT NULL,
                    ck_state_serialization BLOB,
                    account_identifier_hash TEXT,
                    last_fetch_at TEXT,
                    last_send_at TEXT
                );

                CREATE TABLE field_versions (
                    object_type TEXT NOT NULL,
                    object_id TEXT NOT NULL,
                    field_name TEXT NOT NULL,
                    hlc TEXT NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    PRIMARY KEY (object_type, object_id, field_name)
                );

                CREATE TABLE merge_conflicts (
                    id TEXT PRIMARY KEY NOT NULL,
                    object_type TEXT NOT NULL,
                    object_id TEXT NOT NULL,
                    field_name TEXT NOT NULL,
                    local_value TEXT,
                    remote_value TEXT,
                    ancestor_value TEXT,
                    detected_at TEXT NOT NULL,
                    resolution TEXT,
                    resolved_at TEXT
                );

                CREATE TABLE operation_journal (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    request_id TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    command TEXT NOT NULL,
                    object_type TEXT NOT NULL,
                    object_id TEXT NOT NULL,
                    before_revision INTEGER,
                    after_revision INTEGER,
                    effect_summary TEXT,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE pending_operations (
                    id TEXT PRIMARY KEY NOT NULL,
                    request_id TEXT NOT NULL UNIQUE,
                    command TEXT NOT NULL,
                    object_type TEXT NOT NULL,
                    object_id TEXT NOT NULL,
                    stage TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    retry_count INTEGER NOT NULL DEFAULT 0,
                    last_error_code TEXT
                );

                CREATE INDEX idx_task_series_mission ON task_series(mission_id);
                CREATE INDEX idx_task_series_updated ON task_series(updated_at);
                CREATE INDEX idx_occurrences_series ON task_occurrences(series_id);
                CREATE INDEX idx_occurrences_due ON task_occurrences(planned_due);
                CREATE INDEX idx_occurrences_status ON task_occurrences(status);
                CREATE INDEX idx_habits_mission ON habits(mission_id);
                CREATE INDEX idx_checkins_habit_period ON checkins(habit_id, period_key);
                CREATE INDEX idx_outbox_enqueued ON cloud_outbox(enqueued_at);
                CREATE INDEX idx_journal_object ON operation_journal(object_type, object_id);
                CREATE INDEX idx_conflicts_open ON merge_conflicts(object_type, object_id);
                """)
        }
        migrator.registerMigration("v2_outbox_payload_and_ancestors") { db in
            try db.execute(sql: """
                ALTER TABLE cloud_outbox ADD COLUMN payload_json TEXT;
                ALTER TABLE cloud_outbox ADD COLUMN fields_json TEXT;
                ALTER TABLE cloud_outbox ADD COLUMN modified_by_device TEXT;
                ALTER TABLE cloud_outbox ADD COLUMN updated_at TEXT;
                ALTER TABLE cloud_outbox ADD COLUMN deleted_at TEXT;

                CREATE TABLE IF NOT EXISTS field_ancestors (
                    object_type TEXT NOT NULL,
                    object_id TEXT NOT NULL,
                    field_name TEXT NOT NULL,
                    value TEXT,
                    hlc TEXT NOT NULL,
                    PRIMARY KEY (object_type, object_id, field_name)
                );
                """)
        }
        migrator.registerMigration("v3_cloud_inbox") { db in
            try db.execute(sql: """
                CREATE TABLE cloud_inbox (
                    id TEXT PRIMARY KEY NOT NULL,
                    record_type TEXT NOT NULL,
                    record_name TEXT NOT NULL,
                    operation TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    payload_json TEXT NOT NULL,
                    fields_json TEXT,
                    modified_by_device TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT,
                    received_at TEXT NOT NULL,
                    retry_count INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    status TEXT NOT NULL,
                    UNIQUE(record_type, record_name)
                );
                CREATE INDEX idx_inbox_status ON cloud_inbox(status, received_at);
                """)
        }
        migrator.registerMigration("v4_countdown_cloudkit") { db in
            try db.execute(sql: """
                CREATE TABLE managed_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    external_id TEXT,
                    title TEXT NOT NULL,
                    calendar_title TEXT,
                    calendar_identifier TEXT,
                    calendar_system TEXT NOT NULL,
                    recurrence TEXT NOT NULL,
                    date TEXT,
                    time TEXT,
                    start_year INTEGER,
                    lunar_month INTEGER,
                    lunar_day INTEGER,
                    lunar_leap_month_policy TEXT NOT NULL,
                    invalid_lunar_day_policy TEXT NOT NULL,
                    is_all_day INTEGER NOT NULL,
                    alert_days_json TEXT NOT NULL,
                    notes TEXT,
                    select_for_countdown INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT
                );

                CREATE TABLE countdown_selections (
                    id TEXT PRIMARY KEY NOT NULL,
                    mode TEXT NOT NULL,
                    calendar_identifier TEXT,
                    calendar_title TEXT NOT NULL,
                    event_identifier TEXT,
                    external_identifier TEXT,
                    managed_record_id TEXT,
                    event_title TEXT NOT NULL,
                    occurrence_date TEXT,
                    selected_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    modified_by_device TEXT NOT NULL,
                    deleted_at TEXT
                );

                CREATE TABLE countdown_preferences (
                    id TEXT PRIMARY KEY NOT NULL,
                    pinned_selection_id TEXT,
                    revision INTEGER NOT NULL,
                    updated_at TEXT NOT NULL,
                    modified_by_device TEXT NOT NULL
                );

                CREATE TABLE countdown_hidden_calendars (
                    calendar_identifier TEXT PRIMARY KEY NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE INDEX idx_managed_events_updated ON managed_events(updated_at);
                CREATE INDEX idx_countdown_selections_updated ON countdown_selections(updated_at);
                """)
        }
        return migrator
    }
}
