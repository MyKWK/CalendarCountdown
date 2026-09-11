import Foundation

public enum DomainLinkKind: String, Sendable {
    case event
    case task
    case mission
    case habit
}

public struct DomainLink: Equatable, Sendable {
    public var kind: DomainLinkKind
    public var id: UUID
    public var occurrenceKey: String?
    public var checkInID: UUID?

    /// The legacy countdown feature owns `event` links. Only the newer task,
    /// mission, and habit links belong to the domain projection reconciler.
    public var isSystemProjection: Bool {
        switch kind {
        case .task, .mission, .habit: true
        case .event: false
        }
    }

    public init(kind: DomainLinkKind, id: UUID, occurrenceKey: String? = nil, checkInID: UUID? = nil) {
        self.kind = kind
        self.id = id
        self.occurrenceKey = occurrenceKey
        self.checkInID = checkInID
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = ProductConstants.managedURLScheme
        components.host = kind.rawValue
        switch (kind, occurrenceKey, checkInID) {
        case (.task, let key?, _):
            components.path = "/\(id.uuidString.lowercased())/occurrence/\(Self.encodePath(key))"
        case (.habit, _, let checkInID?):
            components.path = "/\(id.uuidString.lowercased())/checkin/\(checkInID.uuidString.lowercased())"
        default:
            components.path = "/\(id.uuidString.lowercased())"
        }
        return components.url
    }

    public var urlString: String {
        url?.absoluteString ?? ""
    }

    public static func task(_ id: UUID, occurrenceKey: String? = nil) -> DomainLink {
        DomainLink(kind: .task, id: id, occurrenceKey: occurrenceKey)
    }

    public static func mission(_ id: UUID) -> DomainLink {
        DomainLink(kind: .mission, id: id)
    }

    public static func habit(_ id: UUID, checkInID: UUID? = nil) -> DomainLink {
        DomainLink(kind: .habit, id: id, checkInID: checkInID)
    }

    public static func event(_ id: UUID) -> DomainLink {
        DomainLink(kind: .event, id: id)
    }

    public static func parse(_ value: String) -> DomainLink? {
        guard let url = URL(string: value) else { return nil }
        return parse(url)
    }

    public static func parse(_ url: URL) -> DomainLink? {
        guard url.scheme == ProductConstants.managedURLScheme,
              let host = url.host,
              let kind = DomainLinkKind(rawValue: host)
        else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first, let id = UUID(uuidString: first) else {
            return nil
        }
        if parts.count >= 3, parts[1] == "occurrence" {
            return DomainLink(kind: kind, id: id, occurrenceKey: decodePath(parts[2]))
        }
        if parts.count >= 3, parts[1] == "checkin", let checkInID = UUID(uuidString: parts[2]) {
            return DomainLink(kind: kind, id: id, checkInID: checkInID)
        }
        if parts.count == 1 {
            return DomainLink(kind: kind, id: id)
        }
        return nil
    }

    private static func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func decodePath(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }
}
