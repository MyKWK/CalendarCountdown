import CalendarCountdownCore
import Foundation

enum BrokerClient {
    static func call(
        method: String,
        paramsJSON: String = "{}",
        options: WriteOptions,
        launchIfNeeded: Bool = true
    ) throws -> String {
        let token = try BrokerTokenStore.load()
        let request = BrokerRequest(
            method: method,
            params: paramsJSON,
            token: token,
            options: BrokerWriteOptions(options)
        )
        do {
            let result = try roundTrip(request)
            DiagnosticLogger.shared.log(
                .debug,
                category: .broker,
                event: "broker.client.roundtrip.completed",
                correlationID: options.requestID,
                metadata: ["method": method]
            )
            return result
        } catch let error as DomainError where error.code == .brokerUnavailable && launchIfNeeded {
            DiagnosticLogger.shared.log(
                .warning,
                category: .broker,
                event: "broker.client.launch_requested",
                correlationID: options.requestID,
                metadata: ["method": method]
            )
            try launchApp()
            let deadline = Date().addingTimeInterval(ProductConstants.brokerLaunchTimeout)
            var lastError = error
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
                do {
                    let result = try roundTrip(request)
                    DiagnosticLogger.shared.log(
                        .notice,
                        category: .broker,
                        event: "broker.client.recovered",
                        correlationID: options.requestID,
                        metadata: ["method": method]
                    )
                    return result
                } catch let retry as DomainError {
                    lastError = retry
                }
            }
            DiagnosticLogger.shared.log(
                .error,
                category: .broker,
                event: "broker.client.unavailable",
                correlationID: options.requestID,
                metadata: DiagnosticLogger.errorMetadata(lastError).merging([
                    "method": method
                ]) { current, _ in current }
            )
            throw lastError
        }
    }

    static func emitResult(_ json: String) {
        if let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object) {
            let wrapped = ["ok": true, "data": object] as [String: Any]
            if let output = try? JSONSerialization.data(withJSONObject: wrapped, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: output, encoding: .utf8) {
                print(text)
                return
            }
        }
        print("""
        {
          "ok" : true,
          "data" : \(json)
        }
        """)
    }

    private static func roundTrip(_ request: BrokerRequest) throws -> String {
        let path = try SharedContainer.brokerSocketURL().path
        let fd = try UnixLineSocket.connect(path: path)
        defer { UnixLineSocket.close(fd) }
        let payload = try JSONCoding.encoder(pretty: false).encode(request)
        try UnixLineSocket.writeLine(fd, String(decoding: payload, as: UTF8.self))
        let line = try UnixLineSocket.readLine(fd)
        let response = try JSONCoding.decoder().decode(BrokerResponse.self, from: Data(line.utf8))
        if response.ok, let json = response.resultJSON {
            return json
        }
        if let error = response.error {
            throw DomainError(
                code: DomainErrorCode(rawValue: error.code) ?? .operationFailed,
                message: error.message,
                details: error.details,
                retryable: error.retryable
            )
        }
        throw DomainError(code: .operationFailed, message: "Broker 未返回结果。")
    }

    private static func launchApp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", ProductConstants.appBundleIdentifier]
        try process.run()
    }
}
