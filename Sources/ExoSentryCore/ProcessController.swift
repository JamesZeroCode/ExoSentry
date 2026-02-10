import Foundation

public protocol ProcessControlling: Sendable {
    func terminateProcess(named: String) throws
    func launchProcess(named: String) throws
}

public enum ProcessControlError: Error, Equatable {
    case commandFailed(Int32)
    case launchFailed
}

public struct SystemProcessController: ProcessControlling {
    public init() {}

    public func terminateProcess(named: String) throws {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", trimmed]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw ProcessControlError.commandFailed(process.terminationStatus)
        }
    }

    public func launchProcess(named: String) throws {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [trimmed]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw ProcessControlError.launchFailed
        }
    }
}
