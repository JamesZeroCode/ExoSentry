import Foundation

public protocol NetworkProbing: Sendable {
    func probe() throws -> ProbeSnapshot
}

public enum NetworkProbeError: Error, Equatable {
    case commandFailed(Int32)
    case invalidOutput
}

public struct SystemNetworkProbeService: NetworkProbing {
    public let internetHost: String

    public init(internetHost: String = "1.1.1.1") {
        self.internetHost = internetHost
    }

    public func probe() throws -> ProbeSnapshot {
        let gatewayHost = try defaultGatewayAddress()
        let gatewayReachable = ping(host: gatewayHost)
        let internetReachable = ping(host: internetHost)
        return ProbeSnapshot(gatewayReachable: gatewayReachable, internetReachable: internetReachable)
    }

    private func defaultGatewayAddress() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        // Read stdout BEFORE waitUntilExit to avoid pipe buffer deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NetworkProbeError.commandFailed(process.terminationStatus)
        }
        guard let output = String(data: data, encoding: .utf8) else {
            throw NetworkProbeError.invalidOutput
        }
        for line in output.split(separator: "\n") {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("gateway:") {
                return text.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        throw NetworkProbeError.invalidOutput
    }

    private func ping(host: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "1", host]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
