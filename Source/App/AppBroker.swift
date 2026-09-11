import CalendarCountdownCalendar
import CalendarCountdownCore
import CalendarCountdownPersistence
import Darwin
import Foundation

final class AppBrokerServer: @unchecked Sendable {
    private var workspace: Workspace
    private let projections: AppleProjectionRuntime
    private let profileSession: CloudProfileSession
    private var cloudEngine: CloudKitSyncEngine?
    private var listener: Int32 = -1
    private var thread: Thread?
    private(set) var isListening = false
    private let token: String

    init(
        workspace: Workspace,
        projections: AppleProjectionRuntime,
        token: String,
        profileSession: CloudProfileSession
    ) {
        self.workspace = workspace
        self.projections = projections
        self.token = token
        self.profileSession = profileSession
    }

    func replaceWorkspace(_ workspace: Workspace) {
        self.workspace = workspace
    }

    func attachCloudEngine(_ engine: CloudKitSyncEngine) {
        cloudEngine = engine
    }

    func start() throws {
        let url = try SharedContainer.brokerSocketURL()
        listener = try UnixLineSocket.listen(path: url.path)
        isListening = true
        let server = self
        let thread = Thread {
            server.acceptLoop()
        }
        thread.name = "CalendarCountdown.Broker"
        thread.start()
        self.thread = thread
        DiagnosticLogger.shared.log(
            .notice,
            category: .broker,
            event: "broker.started",
            metadata: ["socket_file": url.lastPathComponent]
        )
    }

    func stop() {
        DiagnosticLogger.shared.log(.notice, category: .broker, event: "broker.stopping")
        isListening = false
        if listener >= 0 {
            UnixLineSocket.close(listener)
            listener = -1
        }
        if let path = try? SharedContainer.brokerSocketURL().path {
            unlink(path)
        }
    }

    private func acceptLoop() {
        while isListening {
            do {
                let client = try UnixLineSocket.accept(listener)
                handle(client: client)
            } catch {
                if !isListening { break }
                DiagnosticLogger.shared.log(
                    .warning,
                    category: .broker,
                    event: "broker.accept.failed",
                    metadata: DiagnosticLogger.errorMetadata(error)
                )
            }
        }
    }

    private func handle(client fd: Int32) {
        defer { UnixLineSocket.close(fd) }
        do {
            let uid = UnixLineSocket.peerUID(fd)
            guard uid == getuid() else {
                DiagnosticLogger.shared.log(
                    .warning,
                    category: .broker,
                    event: "broker.peer.rejected",
                    metadata: ["peer_uid_available": String(uid != nil)]
                )
                let denied = BrokerResponse(
                    id: UUID(),
                    ok: false,
                    error: APIErrorPayload(DomainError(code: .brokerAuthFailed, message: "Broker 拒绝非本用户进程。"))
                )
                try UnixLineSocket.writeLine(fd, encode(denied))
                return
            }
            let line = try UnixLineSocket.readLine(fd)
            let request = try JSONCoding.decoder().decode(BrokerRequest.self, from: Data(line.utf8))
            DiagnosticLogger.shared.log(
                .info,
                category: .broker,
                event: "broker.request.received",
                correlationID: request.options.requestID,
                metadata: [
                    "method": request.method,
                    "actor": request.options.actor.rawValue,
                    "dry_run": String(request.options.dryRun)
                ]
            )
            let response = awaitResponse(request)
            try UnixLineSocket.writeLine(fd, encode(response))
        } catch {
            DiagnosticLogger.shared.log(
                .error,
                category: .broker,
                event: "broker.request.failed_before_dispatch",
                metadata: DiagnosticLogger.errorMetadata(error)
            )
            let failure = BrokerResponse(
                id: UUID(),
                ok: false,
                error: APIErrorPayload(
                    error as? DomainError ?? DomainError(code: .operationFailed, message: error.localizedDescription)
                )
            )
            try? UnixLineSocket.writeLine(fd, encode(failure))
        }
    }

    private func awaitResponse(_ request: BrokerRequest) -> BrokerResponse {
        if request.token != token {
            DiagnosticLogger.shared.log(
                .warning,
                category: .broker,
                event: "broker.authentication.failed",
                correlationID: request.options.requestID,
                metadata: ["method": request.method]
            )
            return BrokerResponse(
                id: request.id,
                ok: false,
                error: APIErrorPayload(DomainError(code: .brokerAuthFailed, message: "Broker token 无效。")),
                meta: APIMeta(requestId: request.id)
            )
        }
        let options = request.options.makeWriteOptions()
        if request.method == "projections.reconcile" {
            return runProjection(request: request, dryRun: options.dryRun)
        }
        if request.method == "sync.now" {
            return runCloudSync(request: request)
        }
        if request.method == "cloud.set-mode" || request.method == "sync.set-mode" {
            return runSetCloudMode(request: request, options: options)
        }
        do {
            let access = projections.accessStates()
            let router = ApplicationRouter(
                workspace: workspace,
                brokerListening: isListening,
                remindersAccess: access.reminders.rawValue,
                eventsAccess: access.events.rawValue
            )
            let resultJSON = try router.dispatch(
                method: request.method,
                paramsJSON: request.params,
                options: options
            )
            if isWrite(request.method), !options.dryRun {
                let workspace = self.workspace
                let projections = self.projections
                let cloudEngine = self.cloudEngine
                Task { @Sendable in
                    _ = try? await workspace.reconcileProjections(using: projections)
                    if (try? workspace.cloud.mode()) == .iCloud {
                        _ = try? await cloudEngine?.syncNow()
                    }
                }
            }
            return BrokerResponse(
                id: request.id,
                ok: true,
                resultJSON: resultJSON,
                meta: APIMeta(requestId: request.options.requestID)
            )
        } catch let error as DomainError {
            return BrokerResponse(
                id: request.id,
                ok: false,
                error: APIErrorPayload(error),
                meta: APIMeta(requestId: request.options.requestID)
            )
        } catch {
            return BrokerResponse(
                id: request.id,
                ok: false,
                error: APIErrorPayload(DomainError(code: .operationFailed, message: error.localizedDescription)),
                meta: APIMeta(requestId: request.options.requestID)
            )
        }
    }

    private func runSetCloudMode(request: BrokerRequest, options: WriteOptions) -> BrokerResponse {
        do {
            let resultJSON = try ApplicationRouter(
                workspace: workspace,
                brokerListening: isListening
            ).dispatch(
                method: request.method,
                paramsJSON: request.params,
                options: options
            )
            if (try? workspace.cloud.mode()) == .iCloud {
                let engine = try resolvedCloudEngine()
                cloudEngine = engine
                return runCloudSync(request: request)
            }
            return BrokerResponse(
                id: request.id,
                ok: true,
                resultJSON: resultJSON,
                meta: APIMeta(requestId: request.options.requestID)
            )
        } catch let error as DomainError {
            return BrokerResponse(
                id: request.id,
                ok: false,
                error: APIErrorPayload(error),
                meta: APIMeta(requestId: request.options.requestID)
            )
        } catch {
            return BrokerResponse(
                id: request.id,
                ok: false,
                error: APIErrorPayload(DomainError(code: .operationFailed, message: error.localizedDescription)),
                meta: APIMeta(requestId: request.options.requestID)
            )
        }
    }

    private func resolvedCloudEngine() throws -> CloudKitSyncEngine {
        if let cloudEngine {
            return cloudEngine
        }
        let engine = try CloudKitEngineFactory.make(
            workspace: workspace,
            profileSession: profileSession,
            automaticallySync: false
        )
        _ = try engine.start()
        return engine
    }

    private func runProjection(request: BrokerRequest, dryRun: Bool) -> BrokerResponse {
        let workspace = self.workspace
        let projections = self.projections
        return runBlocking {
            do {
                let started = Date()
                let report = try await workspace.reconcileProjections(using: projections, dryRun: dryRun)
                DiagnosticLogger.shared.log(
                    report.failed == 0 ? .notice : .warning,
                    category: .projection,
                    event: "projection.reconcile.completed",
                    correlationID: request.options.requestID,
                    metadata: [
                        "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                        "desired": String(report.desired),
                        "applied": String(report.applied),
                        "failed": String(report.failed),
                        "dry_run": String(report.dryRun)
                    ]
                )
                return BrokerResponse(
                    id: request.id,
                    ok: true,
                    resultJSON: String(decoding: try JSONCoding.encoder(pretty: false).encode(report), as: UTF8.self),
                    meta: APIMeta(requestId: request.id)
                )
            } catch {
                DiagnosticLogger.shared.log(
                    .error,
                    category: .projection,
                    event: "projection.reconcile.failed",
                    correlationID: request.options.requestID,
                    metadata: DiagnosticLogger.errorMetadata(error)
                )
                return BrokerResponse(
                    id: request.id,
                    ok: false,
                    error: APIErrorPayload(error as? DomainError ?? DomainError(code: .projectionFailed, message: error.localizedDescription)),
                    meta: APIMeta(requestId: request.id)
                )
            }
        }
    }

    private func runCloudSync(request: BrokerRequest) -> BrokerResponse {
        let workspace = self.workspace
        let cloudEngine = self.cloudEngine
        return runBlocking {
            do {
                let status: CloudSyncStatus
                if let cloudEngine {
                    status = try await cloudEngine.syncNow()
                } else {
                    status = try workspace.cloud.status()
                }
                return BrokerResponse(
                    id: request.id,
                    ok: true,
                    resultJSON: String(decoding: try JSONCoding.encoder(pretty: false).encode(status), as: UTF8.self),
                    meta: APIMeta(requestId: request.id)
                )
            } catch {
                DiagnosticLogger.shared.log(
                    .error,
                    category: .sync,
                    event: "broker.sync.failed",
                    correlationID: request.options.requestID,
                    metadata: DiagnosticLogger.errorMetadata(error)
                )
                return BrokerResponse(
                    id: request.id,
                    ok: false,
                    error: APIErrorPayload(error as? DomainError ?? DomainError(code: .icloudUnavailable, message: error.localizedDescription, retryable: true)),
                    meta: APIMeta(requestId: request.id)
                )
            }
        }
    }

    private func runBlocking(_ work: @escaping @Sendable () async -> BrokerResponse) -> BrokerResponse {
        let box = BlockingBox<BrokerResponse>()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @Sendable in
            box.value = await work()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }

    private func isWrite(_ method: String) -> Bool {
        !(method.contains(".list") || method.contains(".get") || method.contains(".status")
            || method.contains(".progress") || method.contains(".stats") || method.contains("capabilities")
            || method.contains("doctor") || method.contains("export"))
    }

    private func encode(_ response: BrokerResponse) -> String {
        String(decoding: (try? JSONCoding.encoder(pretty: false).encode(response)) ?? Data(), as: UTF8.self)
    }
}

private final class BlockingBox<Value>: @unchecked Sendable {
    var value: Value?
}
