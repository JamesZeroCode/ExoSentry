import Foundation

protocol NetworkIPControlling {
    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws
    func setV6LinkLocal(service: String) throws
}

enum NetworkIPControlError: Error, Equatable {
    case invalidParameter(String)
    case commandFailed(command: String, code: Int32, details: String)
}

struct SystemNetworkIPController: NetworkIPControlling {
    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws {
        guard !service.isEmpty else {
            throw NetworkIPControlError.invalidParameter("service name is empty")
        }
        guard !ip.isEmpty else {
            throw NetworkIPControlError.invalidParameter("ip address is empty")
        }
        guard !subnet.isEmpty else {
            throw NetworkIPControlError.invalidParameter("subnet mask is empty")
        }

        let normalizedRouter = router.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedRouter.isEmpty || normalizedRouter == "可选" {
            do {
                try runNetworkSetup(arguments: ["-setmanual", service, ip, subnet, "0.0.0.0"])
            } catch {
                try runNetworkSetup(arguments: ["-setmanualwithdhcprouter", service, ip])
            }
            return
        }

        try runNetworkSetup(arguments: ["-setmanual", service, ip, subnet, normalizedRouter])
    }

    func setV6LinkLocal(service: String) throws {
        guard !service.isEmpty else {
            throw NetworkIPControlError.invalidParameter("service name is empty")
        }

        try runNetworkSetup(arguments: ["-setv6LinkLocal", service])
    }

    private func runNetworkSetup(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let command = "/usr/sbin/networksetup \(arguments.joined(separator: " "))"
            throw NetworkIPControlError.commandFailed(command: command, code: process.terminationStatus, details: details)
        }
    }
}

extension NetworkIPControlError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidParameter(let reason):
            return "invalid network IP parameter: \(reason)"
        case .commandFailed(let command, let code, let details):
            if details.isEmpty {
                return "networksetup failed (code: \(code)): \(command)"
            }
            return "networksetup failed (code: \(code)): \(details) [\(command)]"
        }
    }
}
