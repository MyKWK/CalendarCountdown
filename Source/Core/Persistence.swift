import Foundation

public enum SharedContainer {
    public static func rootURL(fileManager: FileManager = .default) throws -> URL {
        // Local packages are ad-hoc signed and therefore have no Apple Team ID.
        // A non-sandboxed host can keep using the established group-container
        // folder directly, while the sandboxed widget uses its own container.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            let url = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers", isDirectory: true)
                .appendingPathComponent(ProductConstants.appGroupIdentifier, isDirectory: true)
                .appendingPathComponent("CalendarCountdown", isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        if let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ProductConstants.appGroupIdentifier
        ) {
            let url = groupURL.appendingPathComponent("CalendarCountdown", isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        return try applicationSupportRootURL(fileManager: fileManager)
    }

    public static func applicationSupportRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = base.appendingPathComponent("CalendarCountdown", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func widgetExtensionSnapshotURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(ProductConstants.widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/CalendarCountdown", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func managedEventsURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("managed-events.json")
    }

    public static func widgetSnapshotURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("widget-snapshot.json")
    }

    public static func selectionsURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("countdown-selections.json")
    }

    public static func trackedEventsURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("tracked-events.json")
    }

    public static func displayPreferencesURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("display-preferences.json")
    }
}

public enum JSONCoding {
    public static func encoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum ManagedEventFileStore {
    public static func load(fileManager: FileManager = .default) throws -> [ManagedEventRecord] {
        let url = try SharedContainer.managedEventsURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONCoding.decoder().decode([ManagedEventRecord].self, from: Data(contentsOf: url))
    }

    public static func save(_ records: [ManagedEventRecord], fileManager: FileManager = .default) throws {
        let url = try SharedContainer.managedEventsURL(fileManager: fileManager)
        let ordered = records.sorted { lhs, rhs in
            if lhs.draft.title == rhs.draft.title { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.draft.title.localizedStandardCompare(rhs.draft.title) == .orderedAscending
        }
        let data = try JSONCoding.encoder().encode(ordered)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public static func upsert(_ draft: ManagedEventDraft, now: Date = Date()) throws -> (record: ManagedEventRecord, wasCreated: Bool) {
        let validated = try draft.validated()
        var records = try load()

        if let externalId = validated.externalId,
           let index = records.firstIndex(where: { $0.draft.externalId == externalId }) {
            records[index].draft = validated
            records[index].updatedAt = now
            try save(records)
            return (records[index], false)
        }

        let record = ManagedEventRecord(draft: validated, createdAt: now, updatedAt: now)
        records.append(record)
        try save(records)
        return (record, true)
    }

    public static func record(id: UUID) throws -> ManagedEventRecord? {
        try load().first(where: { $0.id == id })
    }

    @discardableResult
    public static func replace(id: UUID, draft: ManagedEventDraft, now: Date = Date()) throws -> ManagedEventRecord {
        let validated = try draft.validated()
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ManagedRecordStoreError.recordNotFound(id)
        }
        records[index].draft = validated
        records[index].updatedAt = now
        try save(records)
        return records[index]
    }

    public static func remove(id: UUID) throws -> ManagedEventRecord? {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = records.remove(at: index)
        try save(records)
        return removed
    }
}

public enum ManagedRecordStoreError: LocalizedError {
    case recordNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case let .recordNotFound(id): "找不到本工具记录：\(id.uuidString)。"
        }
    }
}

public enum CountdownSelectionStore {
    public static func load(fileManager: FileManager = .default) throws -> [CountdownSelection] {
        let url = try SharedContainer.selectionsURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONCoding.decoder().decode([CountdownSelection].self, from: Data(contentsOf: url))
    }

    public static func save(_ selections: [CountdownSelection], fileManager: FileManager = .default) throws {
        let url = try SharedContainer.selectionsURL(fileManager: fileManager)
        let data = try JSONCoding.encoder().encode(selections.sorted { $0.selectedAt < $1.selectedAt })
        try data.write(to: url, options: .atomic)
    }

    public static func upsert(_ selection: CountdownSelection) throws {
        var selections = try load()
        if let index = selections.firstIndex(where: { candidate in
            candidate.mode == selection.mode
                && candidate.calendarIdentifier == selection.calendarIdentifier
                && candidate.eventTitle == selection.eventTitle
                && candidate.managedRecordID == selection.managedRecordID
        }) {
            selections[index] = selection
        } else {
            selections.append(selection)
        }
        try save(selections)
    }

    public static func remove(id: UUID) throws {
        var selections = try load()
        selections.removeAll { $0.id == id }
        try save(selections)
    }

    public static func selectedEvents(from events: [CountdownEvent], selections: [CountdownSelection]) -> [CountdownEvent] {
        events.filter { event in selections.contains(where: { $0.matches(event) }) }
    }

    /// Returns the nearest occurrence for every recurring series while leaving
    /// unrelated one-off events untouched, even when their titles are identical.
    public static func nextOccurrences(from events: [CountdownEvent]) -> [CountdownEvent] {
        var seenSeries = Set<String>()
        return events.sorted(by: eventOrder).filter { event in
            guard let seriesIdentifier = event.seriesIdentifier else { return true }
            return seenSeries.insert(seriesIdentifier).inserted
        }
    }

    public static func nextSelectedEvents(from events: [CountdownEvent], selections: [CountdownSelection]) -> [CountdownEvent] {
        let orderedEvents = events.sorted(by: eventOrder)
        let selected = selections.compactMap { selection in
            orderedEvents.first(where: { selection.matches($0) })
        }
        var seen = Set<String>()
        return selected.filter { event in
            seen.insert(event.seriesIdentifier ?? "event:\(event.id)").inserted
        }.sorted(by: eventOrder)
    }

    private static func eventOrder(_ lhs: CountdownEvent, _ rhs: CountdownEvent) -> Bool {
        if lhs.eventDate == rhs.eventDate { return lhs.id < rhs.id }
        return lhs.eventDate < rhs.eventDate
    }
}

public enum CountdownDisplayPreferencesStore {
    public static func load(fileManager: FileManager = .default) -> CountdownDisplayPreferences {
        do {
            let url = try SharedContainer.displayPreferencesURL(fileManager: fileManager)
            guard fileManager.fileExists(atPath: url.path) else { return .init() }
            return try JSONCoding.decoder().decode(
                CountdownDisplayPreferences.self,
                from: Data(contentsOf: url)
            )
        } catch {
            return .init()
        }
    }

    public static func save(
        _ preferences: CountdownDisplayPreferences,
        fileManager: FileManager = .default
    ) throws {
        let data = try JSONCoding.encoder().encode(preferences)
        let url = try SharedContainer.displayPreferencesURL(fileManager: fileManager)
        try data.write(to: url, options: .atomic)
    }
}
