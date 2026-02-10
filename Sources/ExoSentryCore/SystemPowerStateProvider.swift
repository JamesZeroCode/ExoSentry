import Foundation

public protocol PowerStateProviding: Sendable {
    func isCharging() -> Bool
    func isLidClosed() -> Bool
}

public struct SystemPowerStateProvider: PowerStateProviding {
    public init() {}

    public func isCharging() -> Bool {
        guard let output = runProcess("/usr/bin/pmset", arguments: ["-g", "batt"])?.lowercased() else {
            return false
        }
        return output.contains("charging") || output.contains("charged")
    }

    public func isLidClosed() -> Bool {
        guard let output = runProcess("/usr/sbin/ioreg", arguments: ["-r", "-k", "AppleClamshellState", "-d", "4"])?.lowercased() else {
            return false
        }
        if output.contains("\"appleclamshellstate\" = yes") {
            return true
        }
        if output.contains("\"appleclamshellstate\" = no") {
            return false
        }
        return false
    }

    private func runProcess(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
