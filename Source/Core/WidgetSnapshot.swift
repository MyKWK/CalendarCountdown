import Foundation

public struct WidgetSnapshotItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let eventDate: Date
    public let colorHex: String
    public let calendarTitle: String

    public init(id: String, title: String, eventDate: Date, colorHex: String, calendarTitle: String) {
        self.id = id
        self.title = title
        self.eventDate = eventDate
        self.colorHex = colorHex
        self.calendarTitle = calendarTitle
    }

    public init(event: CountdownEvent) {
        id = event.id
        title = event.title
        eventDate = event.eventDate
        colorHex = event.colorHex
        calendarTitle = event.calendarTitle
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let items: [WidgetSnapshotItem]

    public init(generatedAt: Date = Date(), items: [WidgetSnapshotItem]) {
        self.generatedAt = generatedAt
        self.items = items
    }

    public static let empty = WidgetSnapshot(generatedAt: .distantPast, items: [])
}

public struct WidgetTaskItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var due: Date?
    public var isOverdue: Bool

    public init(id: UUID, title: String, due: Date?, isOverdue: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.isOverdue = isOverdue
    }
}

public struct WidgetMissionItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var progress: Double?
    public var icon: String
    public var color: String

    public init(
        id: UUID,
        title: String,
        progress: Double?,
        icon: String = MissionSymbolCatalog.defaultSystemName,
        color: String = MissionColor.defaultValue.rawValue
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.icon = icon
        self.color = MissionColor.canonicalStorageValue(color)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, progress, icon, color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
            ?? MissionSymbolCatalog.defaultSystemName
        color = MissionColor.canonicalStorageValue(
            try container.decodeIfPresent(String.self, forKey: .color)
                ?? MissionColor.defaultValue.rawValue
        )
    }
}

public struct WidgetHabitItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var currentStreak: Int
    public var remaining: String?

    public init(id: UUID, title: String, currentStreak: Int, remaining: String? = nil) {
        self.id = id
        self.title = title
        self.currentStreak = currentStreak
        self.remaining = remaining
    }
}

public struct WidgetSnapshotV2: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var tasks: [WidgetTaskItem]
    public var missions: [WidgetMissionItem]
    public var habits: [WidgetHabitItem]
    public var countdown: [WidgetSnapshotItem]

    public init(
        generatedAt: Date = Date(),
        tasks: [WidgetTaskItem] = [],
        missions: [WidgetMissionItem] = [],
        habits: [WidgetHabitItem] = [],
        countdown: [WidgetSnapshotItem] = []
    ) {
        self.generatedAt = generatedAt
        self.tasks = tasks
        self.missions = missions
        self.habits = habits
        self.countdown = countdown
    }

    public static func save(_ snapshot: WidgetSnapshotV2, fileManager: FileManager = .default) throws {
        let data = try JSONCoding.encoder(pretty: false).encode(snapshot)
        for url in snapshotURLs(fileManager: fileManager) {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    public static func load(fileManager: FileManager = .default) -> WidgetSnapshotV2 {
        for url in snapshotURLs(fileManager: fileManager) {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONCoding.decoder().decode(WidgetSnapshotV2.self, from: data)
            else {
                continue
            }
            return snapshot
        }
        return WidgetSnapshotV2()
    }

    public static func snapshotURLs(fileManager: FileManager = .default) -> [URL] {
        var urls: [URL] = []
        if let own = try? SharedContainer.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("widget-snapshot-v2.json") {
            urls.append(own)
        }
        if let shared = try? SharedContainer.widgetSnapshotV2URL(fileManager: fileManager) {
            urls.append(shared)
        }
        #if os(macOS)
        if Bundle.main.bundleIdentifier == ProductConstants.widgetBundleIdentifier {
            urls.append(SharedContainer.widgetExtensionSnapshotV2URL(fileManager: fileManager))
        }
        #endif
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

public enum WidgetSnapshotStore {
    public static func load(fileManager: FileManager = .default) -> WidgetSnapshot {
        let ownContainerURL = try? SharedContainer.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("widget-snapshot.json")
        let sharedURL = try? SharedContainer.widgetSnapshotURL(fileManager: fileManager)

        for url in [ownContainerURL, sharedURL].compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONCoding.decoder().decode(WidgetSnapshot.self, from: data)
            else { continue }
            return snapshot
        }
        return .empty
    }

    public static func save(events: [CountdownEvent], limit: Int = 50, fileManager: FileManager = .default) throws {
        let items = events.prefix(limit).map(WidgetSnapshotItem.init(event:))
        let snapshot = WidgetSnapshot(items: items)
        let data = try JSONCoding.encoder(pretty: false).encode(snapshot)
        let url = try SharedContainer.widgetSnapshotURL(fileManager: fileManager)
        try data.write(to: url, options: .atomic)

    }
}
