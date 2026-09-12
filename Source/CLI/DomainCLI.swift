import CalendarCountdownCore
import CalendarCountdownPersistence
import Foundation

enum DomainCLI {
    static func handle(
        command: String,
        raw: [String],
        arguments: Arguments
    ) throws -> Bool {
        switch command {
        case "capabilities":
            try CLIArgumentValidator.validate(raw, spec: .command([], positionals: 1))
            try invoke(method: "system.capabilities", params: EmptyParams(), raw: raw, arguments: arguments)
            return true
        case "tasks":
            try handleTasks(raw, arguments: arguments)
            return true
        case "missions":
            try handleMissions(raw, arguments: arguments)
            return true
        case "habits":
            try handleHabits(raw, arguments: arguments)
            return true
        case "cloud", "sync":
            try handleCloud(raw, arguments: arguments, command: command)
            return true
        case "projections":
            try handleProjections(raw, arguments: arguments)
            return true
        case "export":
            let output = try arguments.required("--output")
            try CLIArgumentValidator.validate(
                raw,
                spec: .command([], values: ["--output"], positionals: 1)
            )
            let json = try invokeRaw(method: "export.snapshot", params: EmptyParams(), arguments: arguments)
            try json.data(using: .utf8)?.write(to: URL(fileURLWithPath: output), options: .atomic)
            try CalCountCLI.emit(ExportPathReport(exportedPath: output, schemaVersion: 2))
            return true
        case "mcp":
            try CalCountCLI.requireSubcommand(raw, "serve")
            try CLIArgumentValidator.validate(raw, spec: .command(["--stdio"], positionals: 2))
            try MCPStdioServer(transport: try transport(arguments)).run()
            return true
        default:
            return false
        }
    }

    private static func handleTasks(_ raw: [String], arguments: Arguments) throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("tasks 需要子命令。") }
        switch raw[1] {
        case "list":
            try invoke(
                method: "tasks.list",
                params: TaskListFilter(
                    query: arguments.value("--query"),
                    inboxOnly: arguments.has("--inbox"),
                    openOnly: arguments.has("--open"),
                    completedOnly: arguments.has("--completed"),
                    overdueOnly: arguments.has("--overdue"),
                    limit: Int(arguments.value("--limit") ?? "50") ?? 50
                ),
                raw: raw,
                arguments: arguments,
                spec: .command(["--query", "--inbox", "--open", "--completed", "--overdue", "--limit"], values: ["--query", "--limit"], positionals: 2)
            )
        case "get":
            try invoke(method: "tasks.get", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount tasks get <task-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "create":
            try invoke(method: "tasks.create", params: try decodeInput(CreateTaskCommand.self, arguments: arguments), raw: raw, arguments: arguments, spec: .command([], values: ["--input"], positionals: 2))
        case "update":
            let id = try uuid(raw, index: 2, usage: "calcount tasks update <occurrence-id> --input patch.json")
            let patch = try decodeInput(PatchTaskCommand.self, arguments: arguments)
            try invoke(method: "tasks.update", params: TaskUpdateParams(id: id, patch: patch), raw: raw, arguments: arguments, spec: .command([], values: ["--input"], positionals: 3))
        case "complete":
            let id = try uuid(raw, index: 2, usage: "calcount tasks complete <occurrence-id>")
            try invoke(method: "tasks.complete", params: IDParams(id: id, at: try arguments.value("--at").map(RFC3339.parseRequired)), raw: raw, arguments: arguments, spec: .command([], values: ["--at"], positionals: 3))
        case "reopen":
            try invoke(method: "tasks.reopen", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount tasks reopen <occurrence-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "skip":
            try invoke(method: "tasks.skip", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount tasks skip <occurrence-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "archive":
            try invoke(method: "tasks.archive", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount tasks archive <task-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "delete":
            try invoke(
                method: "tasks.delete",
                params: IDParams(
                    id: try uuid(raw, index: 2, usage: "calcount tasks delete <task-id> [--permanent --confirm-id ID]"),
                    confirmID: arguments.value("--confirm-id").flatMap(UUID.init),
                    permanent: arguments.has("--permanent")
                ),
                raw: raw,
                arguments: arguments,
                spec: .command(["--permanent"], values: ["--confirm-id"], positionals: 3)
            )
        default:
            throw CLIUsageError.message("未知 tasks 子命令：\(raw[1])。")
        }
    }

    private static func handleMissions(_ raw: [String], arguments: Arguments) throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("missions 需要子命令。") }
        switch raw[1] {
        case "list":
            try invoke(method: "missions.list", params: EmptyParams(), raw: raw, arguments: arguments, spec: .command([], positionals: 2))
        case "create":
            try invoke(method: "missions.create", params: try decodeInput(CreateMissionCommand.self, arguments: arguments), raw: raw, arguments: arguments, spec: .command([], values: ["--input"], positionals: 2))
        case "get", "progress":
            try invoke(method: "missions.\(raw[1])", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount missions \(raw[1]) <mission-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "update":
            let id = try uuid(raw, index: 2, usage: "calcount missions update <mission-id>")
            let patch = (try? decodeInput(PatchMissionCommand.self, arguments: arguments))
                ?? PatchMissionCommand()
            try invoke(method: "missions.update", params: MissionUpdateParams(id: id, patch: patch), raw: raw, arguments: arguments, spec: .command([], values: ["--input"], positionals: 3))
        case "complete", "pause", "archive":
            try invoke(method: "missions.\(raw[1])", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount missions \(raw[1]) <mission-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "delete":
            try invoke(
                method: "missions.delete",
                params: IDParams(
                    id: try uuid(raw, index: 2, usage: "calcount missions delete <mission-id> [--permanent --confirm-id ID]"),
                    confirmID: arguments.value("--confirm-id").flatMap(UUID.init),
                    permanent: arguments.has("--permanent")
                ),
                raw: raw,
                arguments: arguments,
                spec: .command(["--permanent"], values: ["--confirm-id"], positionals: 3)
            )
        case "add-task", "remove-task":
            guard raw.count >= 4 else { throw CLIUsageError.message("用法：calcount missions \(raw[1]) <mission-id> <task-id>") }
            try invoke(
                method: "missions.\(raw[1])",
                params: MissionTaskParams(missionID: try parseUUID(raw[2]), seriesID: try parseUUID(raw[3])),
                raw: raw,
                arguments: arguments,
                spec: .command([], positionals: 4)
            )
        default:
            throw CLIUsageError.message("未知 missions 子命令：\(raw[1])。")
        }
    }

    private static func handleHabits(_ raw: [String], arguments: Arguments) throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("habits 需要子命令。") }
        switch raw[1] {
        case "list":
            try invoke(method: "habits.list", params: EmptyParams(), raw: raw, arguments: arguments, spec: .command([], positionals: 2))
        case "create":
            try invoke(method: "habits.create", params: try decodeInput(CreateHabitCommand.self, arguments: arguments), raw: raw, arguments: arguments, spec: .command([], values: ["--input"], positionals: 2))
        case "get", "stats":
            try invoke(method: "habits.\(raw[1])", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount habits \(raw[1]) <habit-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "update":
            let id = try uuid(raw, index: 2, usage: "calcount habits update <habit-id>")
            try invoke(method: "habits.update", params: HabitUpdateParams(id: id, patch: try decodeInput(PatchHabitCommand.self, arguments: arguments)), raw: raw, arguments: arguments, spec: .command([], values: ["--input"], positionals: 3))
        case "checkin":
            try invoke(
                method: "habits.checkin",
                params: IDParams(
                    id: try uuid(raw, index: 2, usage: "calcount habits checkin <habit-id>"),
                    value: arguments.value("--value").flatMap { Decimal(string: $0) },
                    at: try arguments.value("--at").map(RFC3339.parseRequired),
                    fillToTarget: arguments.has("--fill-to-target")
                ),
                raw: raw,
                arguments: arguments,
                spec: .command(["--fill-to-target"], values: ["--value", "--at"], positionals: 3)
            )
        case "undo-checkin":
            try invoke(method: "habits.undo-checkin", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount habits undo-checkin <checkin-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "skip":
            try invoke(
                method: "habits.skip",
                params: IDParams(
                    id: try uuid(raw, index: 2, usage: "calcount habits skip <habit-id> --period KEY"),
                    periodKey: try arguments.required("--period")
                ),
                raw: raw,
                arguments: arguments,
                spec: .command([], values: ["--period"], positionals: 3)
            )
        case "archive":
            try invoke(method: "habits.archive", params: IDParams(id: try uuid(raw, index: 2, usage: "calcount habits archive <habit-id>")), raw: raw, arguments: arguments, spec: .command([], positionals: 3))
        case "delete":
            try invoke(
                method: "habits.delete",
                params: IDParams(
                    id: try uuid(raw, index: 2, usage: "calcount habits delete <habit-id>"),
                    confirmID: arguments.value("--confirm-id").flatMap(UUID.init),
                    permanent: arguments.has("--permanent")
                ),
                raw: raw,
                arguments: arguments,
                spec: .command(["--permanent"], values: ["--confirm-id"], positionals: 3)
            )
        default:
            throw CLIUsageError.message("未知 habits 子命令：\(raw[1])。")
        }
    }

    private static func handleCloud(_ raw: [String], arguments: Arguments, command: String) throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("\(command) 需要子命令。") }
        switch raw[1] {
        case "status":
            try invoke(method: "sync.status", params: EmptyParams(), raw: raw, arguments: arguments, spec: .command([], positionals: 2))
        case "now":
            try invoke(method: "sync.now", params: EmptyParams(), raw: raw, arguments: arguments, spec: .command([], positionals: 2))
        case "mode":
            guard raw.count > 2, let mode = CloudSyncMode(rawValue: raw[2]) else {
                throw CLIUsageError.message("用法：calcount cloud mode iCloud|localOnly")
            }
            try invoke(
                method: "cloud.set-mode",
                params: CloudModeParams(mode: mode),
                raw: raw,
                arguments: arguments,
                spec: .command([], positionals: 3)
            )
        case "export":
            let output = try arguments.required("--output")
            try CLIArgumentValidator.validate(
                raw,
                spec: .command(["--ack"], values: ["--output"], positionals: 2)
            )
            let json = try invokeRaw(
                method: "cloud.export",
                params: IDParams(id: UUID(), ack: arguments.has("--ack")),
                arguments: arguments
            )
            try Data(json.utf8).write(to: URL(fileURLWithPath: output), options: .atomic)
            let bundle = try JSONCoding.decoder().decode(CloudBundle.self, from: Data(json.utf8))
            try CalCountCLI.emit(
                CloudExportReport(
                    exportedPath: output,
                    recordCount: bundle.records.count,
                    acked: arguments.has("--ack") ? bundle.records.count : 0
                )
            )
        case "apply":
            let input = try arguments.required("--input")
            let bundle = try JSONCoding.decoder().decode(CloudBundle.self, from: Data(contentsOf: URL(fileURLWithPath: input)))
            if try transport(arguments) == .direct {
                try CalCountCLI.emit(try Workspace.shared().cloud.apply(bundle))
            } else {
                throw CLIUsageError.message("cloud apply 仅支持 --transport direct 诊断路径。")
            }
        default:
            throw CLIUsageError.message("未知 \(command) 子命令：\(raw[1])。")
        }
    }

    private static func handleProjections(_ raw: [String], arguments: Arguments) throws {
        guard raw.count >= 2 else { throw CLIUsageError.message("projections 需要子命令。") }
        switch raw[1] {
        case "status":
            try invoke(method: "projections.status", params: EmptyParams(), raw: raw, arguments: arguments, spec: .command([], positionals: 2))
        case "set":
            try CLIArgumentValidator.validate(
                raw,
                spec: .command([], values: ["--tasks", "--habits", "--missions"], positionals: 2)
            )
            try invoke(
                method: "projections.set",
                params: ProjectionSettingsParams(
                    projectTasks: boolFlag(arguments.value("--tasks")),
                    projectHabits: boolFlag(arguments.value("--habits")),
                    projectMissions: boolFlag(arguments.value("--missions"))
                ),
                raw: raw,
                arguments: arguments
            )
        case "reconcile":
            try invoke(method: "projections.reconcile", params: EmptyParams(), raw: raw, arguments: arguments, spec: .command([], positionals: 2))
        default:
            throw CLIUsageError.message("未知 projections 子命令：\(raw[1])。")
        }
    }

    private static func invoke<T: Encodable>(
        method: String,
        params: T,
        raw: [String],
        arguments: Arguments,
        spec: ArgumentSpec? = nil
    ) throws {
        if let spec {
            try CLIArgumentValidator.validate(raw, spec: spec)
        }
        let json = try invokeRaw(method: method, params: params, arguments: arguments)
        BrokerClient.emitResult(json)
    }

    private static func invokeRaw<T: Encodable>(
        method: String,
        params: T,
        arguments: Arguments
    ) throws -> String {
        let paramsJSON = String(decoding: try JSONCoding.encoder(pretty: false).encode(params), as: UTF8.self)
        let options = writeOptions(arguments)
        switch try transport(arguments) {
        case .direct:
            return try ApplicationRouter(workspace: Workspace.shared()).dispatch(
                method: method,
                paramsJSON: paramsJSON,
                options: options
            )
        case .broker:
            return try BrokerClient.call(method: method, paramsJSON: paramsJSON, options: options)
        }
    }

    private static func transport(_ arguments: Arguments) throws -> CLITransport {
        guard let value = arguments.value("--transport") else { return .broker }
        switch value {
        case "direct":
            return .direct
        case "broker":
            return .broker
        default:
            throw DomainError(code: .unknownArgument, message: "未知 --transport 值：\(value)。")
        }
    }

    private static func boolFlag(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "on", "true", "1", "yes":
            return true
        case "off", "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    private static func writeOptions(_ arguments: Arguments) -> WriteOptions {
        WriteOptions(
            dryRun: arguments.has("--dry-run"),
            idempotencyKey: arguments.value("--idempotency-key"),
            ifRevision: arguments.value("--if-revision").flatMap(Int64.init),
            actor: .cli
        )
    }

    private static func decodeInput<T: Decodable>(_ type: T.Type, arguments: Arguments) throws -> T {
        let raw: Data
        if let path = arguments.value("--input") {
            if path == "-" {
                raw = FileHandle.standardInput.readDataToEndOfFile()
            } else {
                raw = try Data(contentsOf: URL(fileURLWithPath: path))
            }
        } else {
            throw CLIUsageError.message("写操作需要 --input file.json 或 --input -。")
        }
        return try JSONCoding.decoder().decode(T.self, from: raw)
    }

    private static func uuid(_ raw: [String], index: Int, usage: String) throws -> UUID {
        guard raw.count > index else { throw CLIUsageError.message("用法：\(usage)。") }
        return try parseUUID(raw[index])
    }

    private static func parseUUID(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw CLIUsageError.message("无效的 UUID：\(value)。")
        }
        return id
    }
}

private enum CLITransport {
    case broker
    case direct
}

private struct EmptyParams: Codable {}

private struct ExportPathReport: Codable {
    var exportedPath: String
    var schemaVersion: Int
}

private struct MCPStdioServer {
    var transport: CLITransport = .broker

    func run() throws {
        let workspace: Workspace? = transport == .direct ? try Workspace.shared() : nil
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8) else { continue }
            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                writeJSON([
                    "jsonrpc": "2.0",
                    "error": ["code": -32700, "message": "Parse error"],
                    "id": NSNull()
                ])
                continue
            }
            guard let method = payload["method"] as? String else {
                writeJSON([
                    "jsonrpc": "2.0",
                    "error": ["code": -32600, "message": "Invalid Request"],
                    "id": payload["id"] ?? NSNull()
                ])
                continue
            }
            let isNotification = payload["id"] == nil || method.hasPrefix("notifications/")
            if isNotification {
                continue
            }
            let id = payload["id"]
            do {
                let result = try handle(method: method, payload: payload, workspace: workspace)
                var envelope: [String: Any] = ["jsonrpc": "2.0", "result": result]
                envelope["id"] = id
                writeJSON(envelope)
            } catch {
                let domain = error as? DomainError
                var envelope: [String: Any] = [
                    "jsonrpc": "2.0",
                    "error": [
                        "code": -32000,
                        "message": domain?.message ?? error.localizedDescription,
                        "data": [
                            "code": domain?.code.rawValue ?? "operation_failed",
                            "retryable": domain?.retryable ?? false
                        ]
                    ]
                ]
                envelope["id"] = id
                writeJSON(envelope)
            }
        }
    }

    private func handle(method: String, payload: [String: Any], workspace: Workspace?) throws -> Any {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "calendarcountdown", "version": ProductConstants.version]
            ]
        case "tools/list":
            return ["tools": Self.toolList()]
        case "tools/call":
            return try call(payload["params"] as? [String: Any] ?? [:], workspace: workspace)
        case "notifications/initialized", "ping":
            return [:]
        default:
            throw DomainError(code: .usage, message: "unknown_method: \(method)")
        }
    }

    private func call(_ params: [String: Any], workspace: Workspace?) throws -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let paramsJSON = String(
            data: (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8),
            encoding: .utf8
        ) ?? "{}"
        let options = WriteOptions(
            dryRun: arguments["dryRun"] as? Bool ?? false,
            idempotencyKey: arguments["idempotencyKey"] as? String,
            ifRevision: (arguments["ifRevision"] as? NSNumber).map(\.int64Value),
            actor: .mcp
        )
        let json: String
        if let workspace {
            json = try ApplicationRouter(workspace: workspace).dispatch(
                method: name,
                paramsJSON: paramsJSON,
                options: options
            )
        } else {
            json = try BrokerClient.call(method: name, paramsJSON: paramsJSON, options: options)
        }
        return ["content": [["type": "text", "text": json]]]
    }

    private static func toolList() -> [[String: Any]] {
        ApplicationRouter.toolNames.map { name in
            [
                "name": name,
                "description": name,
                "inputSchema": ApplicationRouter.mcpInputSchema(for: name)
            ]
        }
    }

    private func writeJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let output = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: output, encoding: .utf8)
        else { return }
        print(text)
        fflush(stdout)
    }
}
