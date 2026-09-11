import Darwin
import Foundation

public struct ArgumentSpec: Sendable {
    public var flags: Set<String>
    public var valueFlags: Set<String>
    public var positionalLimit: Int

    public init(flags: Set<String>, valueFlags: Set<String>, positionalLimit: Int) {
        self.flags = flags
        self.valueFlags = valueFlags
        self.positionalLimit = positionalLimit
    }

    public static func command(_ flags: [String], values: [String] = [], positionals: Int) -> ArgumentSpec {
        ArgumentSpec(
            flags: Set(flags + values + ["--transport", "--dry-run", "--idempotency-key", "--if-revision"]),
            valueFlags: Set(values + ["--transport", "--idempotency-key", "--if-revision"]),
            positionalLimit: positionals
        )
    }
}

public enum CLIArgumentValidator {
    public static func validate(_ values: [String], spec: ArgumentSpec) throws {
        var index = 0
        var positionals = 0
        while index < values.count {
            let value = values[index]
            if value.hasPrefix("--") {
                guard spec.flags.contains(value) else {
                    throw DomainError(
                        code: .unknownArgument,
                        message: "未知参数：\(value)。"
                    )
                }
                if spec.valueFlags.contains(value) {
                    let next = index + 1
                    guard next < values.count, !values[next].hasPrefix("--") else {
                        throw DomainError(
                            code: .unknownArgument,
                            message: "参数 \(value) 需要值。"
                        )
                    }
                    if value == "--transport" {
                        let transport = values[next]
                        guard transport == "broker" || transport == "direct" else {
                            throw DomainError(
                                code: .unknownArgument,
                                message: "未知 --transport 值：\(transport)。"
                            )
                        }
                    }
                    index += 2
                    continue
                }
                index += 1
            } else {
                positionals += 1
                if positionals > spec.positionalLimit {
                    throw DomainError(
                        code: .unknownArgument,
                        message: "未知参数：\(value)。"
                    )
                }
                index += 1
            }
        }
    }
}

public enum BrokerTokenStore {
    public static func loadOrCreate(fileManager: FileManager = .default) throws -> String {
        let url = try SharedContainer.brokerTokenURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path),
           let existing = try? String(contentsOf: url, encoding: .utf8),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        try token.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }

    public static func load(fileManager: FileManager = .default) throws -> String {
        let url = try SharedContainer.brokerTokenURL(fileManager: fileManager)
        let token = (try? String(contentsOf: url, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw DomainError(code: .brokerUnavailable, message: "App Broker 尚未启动，缺少鉴权 token。", retryable: true)
        }
        return token
    }
}

public enum UnixLineSocket {
    public static func listen(path: String) throws -> Int32 {
        unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DomainError(code: .brokerUnavailable, message: "无法创建 Broker socket。")
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw DomainError(code: .brokerUnavailable, message: "Broker socket 路径过长。")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count + 1) { raw in
                for (index, byte) in pathBytes.enumerated() {
                    raw[index] = byte
                }
                raw[pathBytes.count] = 0
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw DomainError(code: .brokerUnavailable, message: "无法绑定 Broker socket。")
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw DomainError(code: .brokerUnavailable, message: "无法监听 Broker socket。")
        }
        return fd
    }

    public static func connect(path: String) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DomainError(code: .brokerUnavailable, message: "无法连接 App Broker。", retryable: true)
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw DomainError(code: .brokerUnavailable, message: "Broker socket 路径过长。")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count + 1) { raw in
                for (index, byte) in pathBytes.enumerated() {
                    raw[index] = byte
                }
                raw[pathBytes.count] = 0
            }
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw DomainError(code: .brokerUnavailable, message: "App Broker 未运行。", retryable: true)
        }
        return fd
    }

    public static func accept(_ listener: Int32) throws -> Int32 {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else {
            throw DomainError(code: .brokerUnavailable, message: "Broker accept 失败。")
        }
        return fd
    }

    public static func close(_ fd: Int32) {
        Darwin.close(fd)
    }

    public static func peerUID(_ fd: Int32) -> uid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return nil }
        return uid
    }

    public static func writeLine(_ fd: Int32, _ line: String) throws {
        var payload = line
        if !payload.hasSuffix("\n") {
            payload.append("\n")
        }
        try payload.data(using: .utf8)?.withUnsafeBytes { buffer in
            var written = 0
            let bytes = buffer.bindMemory(to: UInt8.self)
            while written < bytes.count {
                let result = Darwin.write(fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if result <= 0 {
                    throw DomainError(code: .brokerUnavailable, message: "Broker 写入失败。")
                }
                written += result
            }
        }
    }

    public static func readLine(_ fd: Int32) throws -> String {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let result = Darwin.read(fd, &byte, 1)
            if result == 0 {
                break
            }
            if result < 0 {
                throw DomainError(code: .brokerUnavailable, message: "Broker 读取失败。")
            }
            if byte == 10 { break }
            data.append(byte)
        }
        guard let line = String(data: data, encoding: .utf8) else {
            throw DomainError.validation("Broker 报文不是 UTF-8。")
        }
        return line
    }
}
