import Foundation

protocol NetworkIPControlling {
    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws
    func setV6LinkLocal(service: String) throws
    func currentIPv4Snapshot(service: String) throws -> (configuration: String, ipAddress: String?)
}

extension NetworkIPControlling {
    func currentIPv4Snapshot(service: String) throws -> (configuration: String, ipAddress: String?) {
        (configuration: "unknown", ipAddress: nil)
    }
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
        // For point-to-point Thunderbolt links without a real gateway, use the
        // interface's own IP as the router (self-route). Using 0.0.0.0 causes
        // configd to periodically reset the interface to a self-assigned IP.
        let effectiveRouter = (normalizedRouter.isEmpty || normalizedRouter == "可选") ? ip : normalizedRouter
        try runNetworkSetup(arguments: ["-setmanual", service, ip, subnet, effectiveRouter])

        // When using self-route (router == ip), configd creates a scoped default
        // route on this interface (e.g. `default via 10.0.0.1 dev en5`). This can
        // steal traffic from the Wi-Fi default route and break internet access.
        // Remove the scoped default route to keep only the subnet route.
        // Wait briefly for configd to finish processing the interface change.
        if effectiveRouter == ip, let device = bsdDevice(forService: service) {
            Thread.sleep(forTimeInterval: 0.5)
            removeScopedDefaultRoute(device: device)
        }
    }

    func setV6LinkLocal(service: String) throws {
        guard !service.isEmpty else {
            throw NetworkIPControlError.invalidParameter("service name is empty")
        }

        try runNetworkSetup(arguments: ["-setv6LinkLocal", service])
    }

    func currentIPv4Snapshot(service: String) throws -> (configuration: String, ipAddress: String?) {
        guard !service.isEmpty else {
            throw NetworkIPControlError.invalidParameter("service name is empty")
        }

        let output = try runNetworkSetupInfo(arguments: ["-getinfo", service])
        var configuration = "unknown"
        var ipAddress: String?

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()

            if lower.contains("dhcp configuration") {
                configuration = "dhcp"
            } else if lower.contains("manual configuration") {
                configuration = "manual"
            }

            if lower.hasPrefix("ip address:") {
                let value = line.dropFirst("IP address:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && value != "none" && value != "(null)" {
                    ipAddress = value
                }
            }
        }

        if let ipAddress, ipAddress.hasPrefix("169.254.") {
            configuration = "selfAssigned"
        }

        return (configuration: configuration, ipAddress: ipAddress)
    }

    /// Resolve the BSD device name (e.g. `en5`) for a network service name by
    /// parsing `networksetup -listnetworkserviceorder`.
    ///
    /// Output format:
    ///   (1) EXO Thunderbolt 2
    ///   (Hardware Port: Thunderbolt 2, Device: en3)
    private func bsdDevice(forService service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listnetworkserviceorder"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }

        var foundService = false
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !foundService {
                // Match "(1) EXO Thunderbolt 2" or "(*) EXO Thunderbolt 2"
                // by stripping the leading "(N) " or "(*) " prefix.
                if line.hasPrefix("("),
                   let closeParen = line.firstIndex(of: ")") {
                    let name = line[line.index(after: closeParen)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    foundService = (name == service)
                }
            } else {
                // Next line: "(Hardware Port: Thunderbolt 2, Device: en3)"
                if let deviceRange = line.range(of: "Device: ") {
                    var device = String(line[deviceRange.upperBound...])
                    // Strip trailing ")"
                    if device.hasSuffix(")") { device.removeLast() }
                    device = device.trimmingCharacters(in: .whitespacesAndNewlines)
                    return device.isEmpty ? nil : device
                }
                foundService = false
            }
        }
        return nil
    }

    /// Remove the scoped default route for a specific interface.
    /// Failure is non-fatal — the route may not exist yet if configd hasn't
    /// created it, or may already have been removed.
    private func removeScopedDefaultRoute(device: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "delete", "default", "-ifscope", device]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return }
        process.waitUntilExit()
        // Ignore exit status — route may not exist.
    }

    private func runNetworkSetup(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        // Read stderr BEFORE waitUntilExit to avoid pipe buffer deadlock.
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let command = "/usr/sbin/networksetup \(arguments.joined(separator: " "))"
            throw NetworkIPControlError.commandFailed(command: command, code: process.terminationStatus, details: details)
        }
    }

    private func runNetworkSetupInfo(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let command = "/usr/sbin/networksetup \(arguments.joined(separator: " "))"
            throw NetworkIPControlError.commandFailed(command: command, code: process.terminationStatus, details: details)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
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
