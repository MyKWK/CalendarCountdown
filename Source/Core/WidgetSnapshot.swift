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

        let widgetURL = SharedContainer.widgetExtensionSnapshotURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: widgetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: widgetURL, options: .atomic)
    }
}
