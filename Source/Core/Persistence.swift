import Foundation

public enum SharedContainer {
    public static func rootURL(fileManager: FileManager = .default) throws -> URL {
        #if os(iOS)
        return try requiredAppGroupRootURL(fileManager: fileManager)
        #else
        // Local packages are ad-hoc signed and therefore have no Apple Team ID.
        // Keep their data in the app's own Application Support directory. Direct
        // access to Library/Group Containers is treated by macOS as access to
        // another app's data and prompts again when an ad-hoc build changes.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            let url = try applicationSupportRootURL(fileManager: fileManager)
            try migrateLocalPackageFilesIfNeeded(to: url, fileManager: fileManager)
            return url
        }

        return try requiredAppGroupRootURL(fileManager: fileManager)
        #endif
    }

    public static func requiredAppGroupRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ProductConstants.appGroupIdentifier
        ) else {
            throw DomainError(
                code: .databaseUnavailable,
                message: "无法访问 App Group 容器 \(ProductConstants.appGroupIdentifier)。App 与 Widget 必须使用同一正式 App Group，不能回退到 Application Support。"
            )
        }
        let url = groupURL.appendingPathComponent("CalendarCountdown", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func migrateLegacySharedFilesIfNeeded(
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws {
        #if os(macOS)
        let legacyRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(ProductConstants.legacyAppGroupIdentifier, isDirectory: true)
            .appendingPathComponent("CalendarCountdown", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyRoot.path) else { return }

        let filenames = [
            "managed-events.json",
            "countdown-selections.json",
            "display-preferences.json",
            "tracked-events.json",
            "widget-snapshot.json",
            "widget-snapshot-v2.json"
        ]
        for filename in filenames {
            let source = legacyRoot.appendingPathComponent(filename)
            let destination = destinationRoot.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else {
                continue
            }
            try fileManager.copyItem(at: source, to: destination)
        }
        #endif
    }

    private static func migrateLocalPackageFilesIfNeeded(
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws {
        #if os(macOS)
        let marker = destinationRoot.appendingPathComponent("local-store-migration-v1")
        guard !fileManager.fileExists(atPath: marker.path) else { return }

        let sourceRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(ProductConstants.appGroupIdentifier, isDirectory: true)
            .appendingPathComponent("CalendarCountdown", isDirectory: true)
        if fileManager.fileExists(atPath: sourceRoot.path) {
            let names = [
                "calendarcountdown-v2.sqlite",
                "calendarcountdown-v2.sqlite-wal",
                "calendarcountdown-v2.sqlite-shm",
                "cloud-profile-catalog.json",
                "managed-events.json",
                "countdown-selections.json",
                "display-preferences.json",
                "tracked-events.json",
                "widget-snapshot.json",
                "widget-snapshot-v2.json",
                "broker.token",
                "countdown-legacy-imported",
                "Backups",
                "Profiles"
            ]
            for name in names {
                let source = sourceRoot.appendingPathComponent(name)
                let destination = destinationRoot.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path),
                      !fileManager.fileExists(atPath: destination.path) else {
                    continue
                }
                try fileManager.copyItem(at: source, to: destination)
            }
        }
        try Data().write(to: marker, options: .atomic)
        #endif
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
        widgetExtensionSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("widget-snapshot.json")
    }

    public static func widgetExtensionSnapshotV2URL(fileManager: FileManager = .default) -> URL {
        widgetExtensionSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("widget-snapshot-v2.json")
    }

    public static func widgetExtensionSupportDirectory(fileManager: FileManager = .default) -> URL {
        #if os(macOS)
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(ProductConstants.widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/CalendarCountdown", isDirectory: true)
        #else
        fileManager.temporaryDirectory.appendingPathComponent(
            "CalendarCountdown-unused-mac-widget-container",
            isDirectory: true
        )
        #endif
    }

    public static func cloudProfileCatalogURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("cloud-profile-catalog.json")
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

    public static func sqliteDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("calendarcountdown-v2.sqlite")
    }

    public static func sqliteBackupDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let url = try rootURL(fileManager: fileManager).appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func widgetSnapshotV2URL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("widget-snapshot-v2.json")
    }

    public static func brokerSocketURL(fileManager: FileManager = .default) throws -> URL {
        #if os(macOS)
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/CalendarCountdown", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("broker.sock")
        #else
        throw DomainError(code: .brokerUnavailable, message: "iOS 不提供本地 Broker。")
        #endif
    }

    public static func brokerTokenURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("broker.token")
    }

    public static func cloudProfileDatabaseURL(
        accountHash: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = try rootURL(fileManager: fileManager)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(accountHash, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("calendarcountdown-v2.sqlite")
    }

    public static func countdownLegacyImportedFlagURL(fileManager: FileManager = .default) throws -> URL {
        try rootURL(fileManager: fileManager).appendingPathComponent("countdown-legacy-imported")
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
        case let .recordNotFound(id):
            AppLocalization.format(
                "error.record_not_found",
                defaultValue: "找不到本工具记录：%@。",
                id.uuidString
            )
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
