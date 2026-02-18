import Foundation

public protocol ProcessSnapshotProviding: Sendable {
    func runningProcessNames() throws -> [String]
}

public enum ProcessSnapshotError: Error, Equatable {
    case commandFailed(Int32)
    case invalidOutput
}

public struct SystemProcessSnapshotProvider: ProcessSnapshotProviding {
    public init() {}

    public func runningProcessNames() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        // Read stdout BEFORE waitUntilExit to avoid deadlock when
        // output exceeds the pipe buffer size (~64 KB).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProcessSnapshotError.commandFailed(process.terminationStatus)
        }

        guard let output = String(data: data, encoding: .utf8) else {
            throw ProcessSnapshotError.invalidOutput
        }

        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}
