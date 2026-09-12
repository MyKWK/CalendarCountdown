import Foundation

public struct FieldSnapshot: Equatable, Sendable {
    public var value: String?
    public var hlc: HybridLogicalTimestamp

    public init(value: String?, hlc: HybridLogicalTimestamp) {
        self.value = value
        self.hlc = hlc
    }
}

public enum FieldMergeDecision: Equatable, Sendable {
    case unchanged
    case takeServer
    case takeClient
    case conflict(local: String?, remote: String?, ancestor: String?)
}

public struct RecordMergeResult: Equatable, Sendable {
    public var fields: [String: String?]
    public var decisions: [String: FieldMergeDecision]
    public var hasUnresolvedConflict: Bool {
        decisions.values.contains { if case .conflict = $0 { true } else { false } }
    }

    public init(fields: [String: String?], decisions: [String: FieldMergeDecision]) {
        self.fields = fields
        self.decisions = decisions
    }
}

public enum CloudMergePolicy {
    public static let markdownFields: Set<String> = [
        "title",
        "description_md",
        "markdownDescription",
        "note"
    ]

    public static let statusFields: Set<String> = [
        "status"
    ]

    public static func mergeField(
        name: String,
        ancestor: FieldSnapshot?,
        server: FieldSnapshot,
        client: FieldSnapshot
    ) -> FieldMergeDecision {
        if server.value == client.value {
            return .unchanged
        }
        if ancestor?.value == server.value {
            return .takeClient
        }
        if ancestor?.value == client.value {
            return .takeServer
        }
        if markdownFields.contains(name) {
            return .conflict(local: client.value, remote: server.value, ancestor: ancestor?.value)
        }
        if statusFields.contains(name) {
            return server.hlc >= client.hlc ? .takeServer : .takeClient
        }
        return server.hlc >= client.hlc ? .takeServer : .takeClient
    }

    public static func merge(
        ancestor: [String: FieldSnapshot],
        server: [String: FieldSnapshot],
        client: [String: FieldSnapshot]
    ) -> RecordMergeResult {
        let names = Set(ancestor.keys).union(server.keys).union(client.keys)
        var fields: [String: String?] = [:]
        var decisions: [String: FieldMergeDecision] = [:]
        for name in names.sorted() {
            guard let serverField = server[name] ?? ancestor[name],
                  let clientField = client[name] ?? ancestor[name]
            else {
                continue
            }
            let decision = mergeField(
                name: name,
                ancestor: ancestor[name],
                server: serverField,
                client: clientField
            )
            decisions[name] = decision
            switch decision {
            case .unchanged:
                fields[name] = clientField.value
            case .takeServer:
                fields[name] = serverField.value
            case .takeClient:
                fields[name] = clientField.value
            case let .conflict(local, remote, _):
                fields[name] = local
                _ = remote
            }
        }
        return RecordMergeResult(fields: fields, decisions: decisions)
    }
}
