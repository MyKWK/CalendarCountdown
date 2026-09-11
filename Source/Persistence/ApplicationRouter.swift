import CalendarCountdownCore
import Foundation

public struct ApplicationRouter: Sendable {
    public let workspace: Workspace
    public let brokerListening: Bool
    public let remindersAccess: String
    public let eventsAccess: String

    public init(
        workspace: Workspace,
        brokerListening: Bool = false,
        remindersAccess: String = "unknown",
        eventsAccess: String = "unknown"
    ) {
        self.workspace = workspace
        self.brokerListening = brokerListening
        self.remindersAccess = remindersAccess
        self.eventsAccess = eventsAccess
    }

    public func dispatch(method: String, paramsJSON: String, options: WriteOptions) throws -> String {
        let started = Date()
        DiagnosticLogger.shared.log(
            .info,
            category: .command,
            event: "command.started",
            correlationID: options.requestID,
            metadata: [
                "method": method,
                "actor": options.actor.rawValue,
                "dry_run": String(options.dryRun),
                "has_idempotency_key": String(options.idempotencyKey != nil),
                "has_revision_guard": String(options.ifRevision != nil)
            ]
        )
        do {
            let result = try dispatchUnlogged(method: method, paramsJSON: paramsJSON, options: options)
            DiagnosticLogger.shared.log(
                .notice,
                category: .command,
                event: "command.completed",
                correlationID: options.requestID,
                metadata: [
                    "method": method,
                    "actor": options.actor.rawValue,
                    "dry_run": String(options.dryRun),
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000))
                ]
            )
            return result
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .command,
                event: "command.failed",
                correlationID: options.requestID,
                metadata: DiagnosticLogger.errorMetadata(error).merging([
                    "method": method,
                    "actor": options.actor.rawValue,
                    "dry_run": String(options.dryRun),
                    "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000))
                ]) { current, _ in current }
            )
            throw error
        }
    }

    private func dispatchUnlogged(method: String, paramsJSON: String, options: WriteOptions) throws -> String {
        let data = Data(paramsJSON.utf8)
        let encoder = JSONCoding.encoder(pretty: false)
        switch method {
        case "system.capabilities":
            return try encode(encoder, workspace.capabilities(broker: brokerListening))
        case "system.doctor":
            return try encode(encoder, workspace.doctor(
                remindersAccess: remindersAccess,
                eventsAccess: eventsAccess,
                brokerListening: brokerListening
            ))
        case "tasks.list":
            let filter = (try? JSONCoding.decoder().decode(TaskListFilterDTO.self, from: data)) ?? TaskListFilterDTO()
            return try encode(encoder, workspace.tasks.list(filter.make()))
        case "tasks.get":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.tasks.get(seriesID: params.id))
        case "tasks.create":
            let command = try decode(CreateTaskCommand.self, data)
            return try encode(encoder, workspace.tasks.create(command, options: options))
        case "tasks.update":
            let params = try decode(TaskUpdateParams.self, data)
            return try encode(encoder, workspace.tasks.patch(occurrenceID: params.id, command: params.patch, options: options))
        case "tasks.complete":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.tasks.complete(occurrenceID: params.id, at: params.at, options: options))
        case "tasks.reopen":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.tasks.reopen(occurrenceID: params.id, options: options))
        case "tasks.skip":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.tasks.skip(occurrenceID: params.id, options: options))
        case "tasks.archive":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.tasks.archive(seriesID: params.id, options: options))
        case "tasks.delete":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.tasks.delete(
                seriesID: params.id,
                permanent: params.permanent ?? false,
                confirmID: params.confirmID,
                options: options
            ))
        case "missions.list":
            return try encode(encoder, workspace.missions.list())
        case "missions.get", "missions.progress":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.missions.get(id: params.id))
        case "missions.create":
            let command = try decode(CreateMissionCommand.self, data)
            return try encode(encoder, workspace.missions.create(command, options: options))
        case "missions.update":
            let params = try decode(MissionUpdateParams.self, data)
            return try encode(encoder, workspace.missions.patch(id: params.id, command: params.patch, options: options))
        case "missions.complete":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.missions.complete(id: params.id, options: options))
        case "missions.pause":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.missions.pause(id: params.id, options: options))
        case "missions.archive":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.missions.archive(id: params.id, options: options))
        case "missions.delete":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.missions.delete(
                id: params.id,
                permanent: params.permanent ?? false,
                confirmID: params.confirmID,
                options: options
            ))
        case "missions.add-task":
            let params = try decode(MissionTaskParams.self, data)
            return try encode(encoder, workspace.missions.addTask(missionID: params.missionID, seriesID: params.seriesID, options: options))
        case "missions.remove-task":
            let params = try decode(MissionTaskParams.self, data)
            return try encode(encoder, workspace.missions.removeTask(missionID: params.missionID, seriesID: params.seriesID, options: options))
        case "habits.list":
            return try encode(encoder, workspace.habits.list())
        case "habits.get", "habits.stats":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.habits.get(id: params.id))
        case "habits.create":
            let command = try decode(CreateHabitCommand.self, data)
            return try encode(encoder, workspace.habits.create(command, options: options))
        case "habits.update":
            let params = try decode(HabitUpdateParams.self, data)
            return try encode(encoder, workspace.habits.update(id: params.id, command: params.patch, options: options))
        case "habits.checkin":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.habits.checkIn(
                habitID: params.id,
                value: params.value,
                at: params.at,
                fillToTarget: params.fillToTarget ?? false,
                note: params.note,
                options: options
            ))
        case "habits.undo-checkin":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.habits.undoCheckIn(id: params.id, options: options))
        case "habits.skip":
            let params = try decode(IDParams.self, data)
            guard let periodKey = params.periodKey else {
                throw DomainError.validation("habits.skip 需要 periodKey。")
            }
            return try encode(encoder, workspace.habits.skipPeriod(habitID: params.id, periodKey: periodKey, options: options))
        case "habits.archive":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.habits.archive(id: params.id, options: options))
        case "habits.delete":
            let params = try decode(IDParams.self, data)
            return try encode(encoder, workspace.habits.delete(
                id: params.id,
                permanent: params.permanent ?? false,
                confirmID: params.confirmID,
                options: options
            ))
        case "cloud.status", "sync.status":
            return try encode(encoder, workspace.cloud.status())
        case "cloud.export":
            let ack = (try? JSONCoding.decoder().decode(IDParams.self, from: data))?.ack ?? false
            let detailed = try workspace.cloud.exportPendingDetailed(ack: ack)
            return try encode(encoder, detailed.bundle)
        case "sync.now":
            return try encode(encoder, workspace.cloud.status())
        case "cloud.set-mode", "sync.set-mode":
            let params = try decode(CloudModeParams.self, data)
            try workspace.cloud.setMode(params.mode)
            return try encode(encoder, workspace.cloud.status())
        case "projections.status":
            return try encode(encoder, ProjectionReconcileReport(desired: try workspace.desiredProjections().count))
        case "projections.set":
            let params = try decode(ProjectionSettingsParams.self, data)
            return try encode(
                encoder,
                workspace.setProjectionSettings(
                    projectTasks: params.projectTasks,
                    projectHabits: params.projectHabits,
                    projectMissions: params.projectMissions,
                    acceptNativeCompletion: params.acceptNativeCompletion
                )
            )
        case "export.snapshot":
            return try encode(encoder, workspace.exchange.exportSnapshot())
        case "import.snapshot":
            let snapshot = try decode(CanonicalSnapshot.self, data)
            return try encode(encoder, workspace.exchange.importSnapshot(snapshot, options: options))
        default:
            throw DomainError(
                code: .usage,
                message: "未知命令：\(method)。"
            )
        }
    }

    public static let toolNames: [String] = [
        "tasks.list", "tasks.get", "tasks.create", "tasks.update",
        "tasks.complete", "tasks.reopen", "tasks.skip", "tasks.archive", "tasks.delete",
        "missions.list", "missions.get", "missions.create", "missions.update",
        "missions.complete", "missions.pause", "missions.archive", "missions.delete", "missions.progress",
        "missions.add-task", "missions.remove-task",
        "habits.list", "habits.get", "habits.create", "habits.update",
        "habits.checkin", "habits.undo-checkin", "habits.stats", "habits.skip",
        "habits.archive", "habits.delete",
        "sync.status", "sync.now", "cloud.set-mode",
        "projections.status", "projections.reconcile", "projections.set",
        "system.capabilities", "system.doctor"
    ]

    public static func mcpInputSchema(for tool: String) -> [String: Any] {
        switch tool {
        case "tasks.create":
            return objectSchema(
                required: ["title"],
                properties: [
                    "title": ["type": "string"],
                    "kind": ["type": "string", "enum": ["deadline", "timeWindow"]],
                    "missionID": ["type": "string", "format": "uuid"],
                    "projectionPolicy": ["type": "string", "enum": ["none", "reminder", "event", "both"]]
                ]
            )
        case "tasks.complete", "tasks.reopen", "tasks.skip", "tasks.get", "tasks.archive":
            return objectSchema(required: ["id"], properties: ["id": ["type": "string", "format": "uuid"]])
        case "tasks.delete":
            return objectSchema(
                required: ["id"],
                properties: [
                    "id": ["type": "string", "format": "uuid"],
                    "permanent": ["type": "boolean"],
                    "confirmID": ["type": "string", "format": "uuid"]
                ]
            )
        case "missions.create":
            return objectSchema(required: ["title"], properties: ["title": ["type": "string"]])
        case "missions.get", "missions.progress", "missions.complete", "missions.pause", "missions.archive":
            return objectSchema(required: ["id"], properties: ["id": ["type": "string", "format": "uuid"]])
        case "habits.create":
            return objectSchema(
                required: ["title", "metric"],
                properties: [
                    "title": ["type": "string"],
                    "metric": ["type": "string", "enum": ["binary", "count", "quantity"]],
                    "targetValue": ["type": "number"],
                    "projectionPolicy": ["type": "string", "enum": ["none", "reminder", "event", "both"]]
                ]
            )
        case "habits.checkin":
            return objectSchema(
                required: ["id"],
                properties: [
                    "id": ["type": "string", "format": "uuid"],
                    "value": ["type": "number"],
                    "fillToTarget": ["type": "boolean"]
                ]
            )
        case "habits.skip":
            return objectSchema(
                required: ["id", "periodKey"],
                properties: [
                    "id": ["type": "string", "format": "uuid"],
                    "periodKey": ["type": "string"]
                ]
            )
        case "cloud.set-mode", "sync.set-mode":
            return objectSchema(
                required: ["mode"],
                properties: ["mode": ["type": "string", "enum": ["localOnly", "iCloud"]]]
            )
        case "projections.set":
            return objectSchema(
                properties: [
                    "projectTasks": ["type": "boolean"],
                    "projectHabits": ["type": "boolean"],
                    "projectMissions": ["type": "boolean"],
                    "acceptNativeCompletion": ["type": "boolean"]
                ]
            )
        default:
            return ["type": "object"]
        }
    }

    private static func objectSchema(
        required: [String] = [],
        properties: [String: [String: Any]]
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONCoding.decoder().decode(type, from: data)
        } catch {
            throw DomainError.validation("无法解码 \(methodName(type)) 参数：\(error.localizedDescription)")
        }
    }

    private func methodName<T>(_ type: T.Type) -> String {
        String(describing: type)
    }

    private func encode<T: Encodable>(_ encoder: JSONEncoder, _ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private struct TaskListFilterDTO: Codable {
    var query: String?
    var missionID: UUID?
    var inboxOnly: Bool?
    var openOnly: Bool?
    var completedOnly: Bool?
    var overdueOnly: Bool?
    var limit: Int?
    var cursor: String?

    func make() -> TaskListFilter {
        TaskListFilter(
            query: query,
            missionID: missionID,
            inboxOnly: inboxOnly ?? false,
            openOnly: openOnly ?? false,
            completedOnly: completedOnly ?? false,
            overdueOnly: overdueOnly ?? false,
            limit: limit ?? 50,
            cursor: cursor
        )
    }
}
