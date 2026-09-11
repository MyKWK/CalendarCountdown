import CalendarCountdownCore
import Foundation
import GRDB

public final class CountdownService: CountdownIntentStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var database: AppDatabase
    public var mirrorsLegacyJSON = false

    public var db: AppDatabase {
        lock.lock()
        defer { lock.unlock() }
        return database
    }

    public init(db: AppDatabase) {
        database = db
    }

    public func attach(db: AppDatabase) {
        lock.lock()
        database = db
        lock.unlock()
    }

    public func importLegacyJSONIfNeeded(fileManager: FileManager = .default) throws {
        let flagURL = try SharedContainer.countdownLegacyImportedFlagURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: flagURL.path) {
            return
        }
        let existing = try loadManagedEvents()
        let selections = try loadSelections()
        if !existing.isEmpty || !selections.isEmpty {
            try Data().write(to: flagURL, options: .atomic)
            return
        }
        let jsonEvents = try ManagedEventFileStore.load(fileManager: fileManager)
        let jsonSelections = try CountdownSelectionStore.load(fileManager: fileManager)
        let jsonPreferences = CountdownDisplayPreferencesStore.load(fileManager: fileManager)
        if jsonEvents.isEmpty && jsonSelections.isEmpty && jsonPreferences.pinnedSelectionID == nil
            && jsonPreferences.untrackedCalendarIdentifiers.isEmpty {
            try Data().write(to: flagURL, options: .atomic)
            return
        }
        try db.write { db in
            for record in jsonEvents {
                try persistManaged(record, operation: "upsert", now: record.updatedAt, db: db)
            }
            for selection in jsonSelections {
                var copy = selection
                copy.modifiedByDevice = self.db.deviceID
                try persistSelection(copy, operation: "upsert", now: copy.updatedAt, db: db)
            }
        }
        try persistPreferences(jsonPreferences, now: Date())
        try Data().write(to: flagURL, options: .atomic)
    }

    public func loadManagedEvents() throws -> [ManagedEventRecord] {
        try db.read { db in
            try ManagedEventRow
                .filter(sql: "deleted_at IS NULL")
                .order(sql: "title ASC")
                .fetchAll(db)
                .map { try $0.domain() }
        }
    }

    public func managedEvent(id: UUID) throws -> ManagedEventRecord? {
        try db.read { db in
            try DomainQueries.managedEvent(db, id: id)
        }
    }

    public func upsertManagedEvent(
        _ draft: ManagedEventDraft,
        now: Date
    ) throws -> (record: ManagedEventRecord, wasCreated: Bool) {
        let validated = try draft.validated()
        let result = try db.write { db in
            if let externalId = validated.externalId,
               let existing = try ManagedEventRow
                .filter(sql: "external_id = ? AND deleted_at IS NULL", arguments: [externalId])
                .fetchOne(db) {
                var record = try existing.domain()
                record.draft = validated
                record.updatedAt = now
                record.revision += 1
                record.modifiedByDevice = self.db.deviceID
                try persistManaged(record, operation: "upsert", now: now, db: db)
                return (record, false)
            }
            let record = ManagedEventRecord(
                draft: validated,
                createdAt: now,
                updatedAt: now,
                revision: 1,
                modifiedByDevice: self.db.deviceID
            )
            try persistManaged(record, operation: "upsert", now: now, db: db)
            return (record, true)
        }
        try mirrorJSONFilesIfNeeded()
        return result
    }

    public func replaceManagedEvent(
        id: UUID,
        draft: ManagedEventDraft,
        now: Date
    ) throws -> ManagedEventRecord {
        let validated = try draft.validated()
        let record = try db.write { db in
            guard var record = try DomainQueries.managedEvent(db, id: id) else {
                throw ManagedRecordStoreError.recordNotFound(id)
            }
            record.draft = validated
            record.updatedAt = now
            record.revision += 1
            record.modifiedByDevice = self.db.deviceID
            try persistManaged(record, operation: "upsert", now: now, db: db)
            return record
        }
        try mirrorJSONFilesIfNeeded()
        return record
    }

    public func removeManagedEvent(id: UUID) throws -> ManagedEventRecord? {
        let record = try db.write { db in
            guard var record = try DomainQueries.managedEvent(db, id: id) else { return nil as ManagedEventRecord? }
            let now = Date()
            record.deletedAt = now
            record.updatedAt = now
            record.revision += 1
            record.modifiedByDevice = self.db.deviceID
            try persistManaged(record, operation: "delete", now: now, db: db)
            return record
        }
        try mirrorJSONFilesIfNeeded()
        return record
    }

    public func loadSelections() throws -> [CountdownSelection] {
        try db.read { db in
            try DomainQueries.countdownSelections(db)
        }
    }

    public func saveSelections(_ selections: [CountdownSelection]) throws {
        let keep = Set(selections.map(\.id))
        let existing = try loadSelections()
        for old in existing where !keep.contains(old.id) {
            try removeSelection(id: old.id)
        }
        for selection in selections {
            try upsertSelection(selection)
        }
    }

    public func upsertSelection(_ selection: CountdownSelection) throws {
        try db.write { db in
            var next = selection
            let now = Date()
            if let existing = try DomainQueries.countdownSelection(db, id: selection.id, includingDeleted: true) {
                next.revision = existing.revision + 1
                next.selectedAt = existing.selectedAt
            } else {
                next.revision = max(selection.revision, 1)
            }
            next.updatedAt = now
            next.deletedAt = nil
            next.modifiedByDevice = self.db.deviceID
            try persistSelection(next, operation: "upsert", now: now, db: db)
        }
        try mirrorJSONFilesIfNeeded()
    }

    public func removeSelection(id: UUID) throws {
        try db.write { db in
            guard var selection = try DomainQueries.countdownSelection(db, id: id) else { return }
            let now = Date()
            selection.deletedAt = now
            selection.updatedAt = now
            selection.revision += 1
            selection.modifiedByDevice = self.db.deviceID
            try persistSelection(selection, operation: "delete", now: now, db: db)
        }
        try mirrorJSONFilesIfNeeded()
    }

    public func loadPreferences() throws -> CountdownDisplayPreferences {
        try db.read { db in
            try DomainQueries.countdownPreferences(db)
        }
    }

    public func savePreferences(_ preferences: CountdownDisplayPreferences) throws {
        try persistPreferences(preferences, now: Date())
    }

    private func persistManaged(
        _ record: ManagedEventRecord,
        operation: String,
        now: Date,
        db: Database
    ) throws {
        try ManagedEventRow(record).save(db)
        try DomainWriter.enqueueEncoded(
            db,
            recordType: "CDManagedEvent",
            recordName: record.id,
            operation: operation,
            revision: record.revision,
            payload: CountdownManagedCloudPayload(record),
            fields: try DomainWriter.fieldSnapshots(
                db,
                objectType: "managed_event",
                objectID: record.id,
                values: ["title": record.draft.title, "notes": record.draft.notes],
                deviceID: record.modifiedByDevice,
                now: record.updatedAt
            ),
            modifiedByDevice: record.modifiedByDevice,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            now: now
        )
    }

    private func persistSelection(
        _ selection: CountdownSelection,
        operation: String,
        now: Date,
        db: Database
    ) throws {
        try CountdownSelectionRow(selection).save(db)
        try DomainWriter.enqueueEncoded(
            db,
            recordType: "CDCountdownSelection",
            recordName: selection.id,
            operation: operation,
            revision: selection.revision,
            payload: CountdownSelectionCloudPayload(selection),
            fields: try DomainWriter.fieldSnapshots(
                db,
                objectType: "countdown_selection",
                objectID: selection.id,
                values: [
                    "event_title": selection.eventTitle,
                    "calendar_title": selection.calendarTitle,
                    "mode": selection.mode.rawValue
                ],
                deviceID: selection.modifiedByDevice,
                now: selection.updatedAt
            ),
            modifiedByDevice: selection.modifiedByDevice,
            updatedAt: selection.updatedAt,
            deletedAt: selection.deletedAt,
            now: now
        )
    }

    private func persistPreferences(_ preferences: CountdownDisplayPreferences, now: Date) throws {
        try db.write { db in
            let id = CloudRecordIdentity.countdownPreferences
            var revision: Int64 = 1
            let pinned = preferences.pinnedSelectionID
            if let row = try CountdownPreferencesRow.fetchOne(db, key: SQLValue.uuid(id)) {
                revision = row.revision + 1
            }
            let payload = CountdownPreferencesCloudPayload(
                id: id,
                pinnedSelectionID: pinned,
                revision: revision,
                updatedAt: now,
                modifiedByDevice: self.db.deviceID
            )
            let row = CountdownPreferencesRow(
                id: SQLValue.uuid(id),
                pinnedSelectionId: pinned.map(SQLValue.uuid),
                revision: revision,
                updatedAt: RFC3339.utcString(from: now),
                modifiedByDevice: SQLValue.uuid(self.db.deviceID)
            )
            try row.save(db)
            try db.execute(sql: "DELETE FROM countdown_hidden_calendars")
            for identifier in preferences.untrackedCalendarIdentifiers {
                try CountdownHiddenCalendarRow(
                    calendarIdentifier: identifier,
                    updatedAt: RFC3339.utcString(from: now)
                ).insert(db)
            }
            try DomainWriter.enqueueEncoded(
                db,
                recordType: "CDCountdownPreferences",
                recordName: id,
                operation: "upsert",
                revision: revision,
                payload: payload,
                modifiedByDevice: self.db.deviceID,
                updatedAt: now,
                now: now
            )
        }
        try mirrorJSONFilesIfNeeded()
    }

    public func refreshLegacyJSONMirror() throws {
        try mirrorJSONFilesIfNeeded()
    }

    private func mirrorJSONFilesIfNeeded() throws {
        guard mirrorsLegacyJSON else { return }
        try mirrorJSONFiles()
    }

    private func mirrorJSONFiles() throws {
        let events = try loadManagedEvents()
        let selections = try loadSelections()
        let preferences = try loadPreferences()
        try ManagedEventFileStore.save(events)
        try CountdownSelectionStore.save(selections)
        try CountdownDisplayPreferencesStore.save(preferences)
    }
}
