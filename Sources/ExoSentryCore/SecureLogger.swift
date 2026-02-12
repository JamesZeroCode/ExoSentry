import Foundation

public enum LogLevel: String, Sendable {
    case info
    case warning
    case error
}

public protocol Logging: Sendable {
    func log(_ level: LogLevel, operation: String, message: String, metadata: [String: String])
}

public final class SecureLogger: Logging, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func log(_ level: LogLevel, operation: String, message: String, metadata: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        let redacted = metadata.mapValues { redact($0) }
        let line = "\(timestamp()) [\(level.rawValue.uppercased())] \(operation) \(message) \(redacted)\n"
        append(line)
    }

    private func redact(_ value: String) -> String {
        if value.count <= 6 {
            return "***"
        }
        let prefix = value.prefix(2)
        let suffix = value.suffix(2)
        return "\(prefix)***\(suffix)"
    }

    private func append(_ line: String) {
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func timestamp() -> String {
        ISO8601Timestamp.string(from: Date())
    }
}
