import Foundation

public protocol CountdownIntentStoring: Sendable {
    func loadManagedEvents() throws -> [ManagedEventRecord]
    func managedEvent(id: UUID) throws -> ManagedEventRecord?
    func upsertManagedEvent(_ draft: ManagedEventDraft, now: Date) throws -> (record: ManagedEventRecord, wasCreated: Bool)
    func replaceManagedEvent(id: UUID, draft: ManagedEventDraft, now: Date) throws -> ManagedEventRecord
    func removeManagedEvent(id: UUID) throws -> ManagedEventRecord?
    func loadSelections() throws -> [CountdownSelection]
    func saveSelections(_ selections: [CountdownSelection]) throws
    func upsertSelection(_ selection: CountdownSelection) throws
    func removeSelection(id: UUID) throws
    func loadPreferences() throws -> CountdownDisplayPreferences
    func savePreferences(_ preferences: CountdownDisplayPreferences) throws
}

public struct JSONCountdownIntentStore: CountdownIntentStoring, @unchecked Sendable {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadManagedEvents() throws -> [ManagedEventRecord] {
        try ManagedEventFileStore.load(fileManager: fileManager)
    }

    public func managedEvent(id: UUID) throws -> ManagedEventRecord? {
        try ManagedEventFileStore.record(id: id)
    }

    public func upsertManagedEvent(
        _ draft: ManagedEventDraft,
        now: Date
    ) throws -> (record: ManagedEventRecord, wasCreated: Bool) {
        try ManagedEventFileStore.upsert(draft, now: now)
    }

    public func replaceManagedEvent(
        id: UUID,
        draft: ManagedEventDraft,
        now: Date
    ) throws -> ManagedEventRecord {
        try ManagedEventFileStore.replace(id: id, draft: draft, now: now)
    }

    public func removeManagedEvent(id: UUID) throws -> ManagedEventRecord? {
        try ManagedEventFileStore.remove(id: id)
    }

    public func loadSelections() throws -> [CountdownSelection] {
        try CountdownSelectionStore.load(fileManager: fileManager)
    }

    public func saveSelections(_ selections: [CountdownSelection]) throws {
        try CountdownSelectionStore.save(selections, fileManager: fileManager)
    }

    public func upsertSelection(_ selection: CountdownSelection) throws {
        try CountdownSelectionStore.upsert(selection)
    }

    public func removeSelection(id: UUID) throws {
        try CountdownSelectionStore.remove(id: id)
    }

    public func loadPreferences() throws -> CountdownDisplayPreferences {
        CountdownDisplayPreferencesStore.load(fileManager: fileManager)
    }

    public func savePreferences(_ preferences: CountdownDisplayPreferences) throws {
        try CountdownDisplayPreferencesStore.save(preferences, fileManager: fileManager)
    }
}
