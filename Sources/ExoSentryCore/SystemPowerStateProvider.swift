import Foundation

public protocol PowerStateProviding: Sendable {
    func isCharging() -> Bool
    func isLidClosed() -> Bool
}

public struct SystemPowerStateProvider: PowerStateProviding {
    public init() {}

    public func isCharging() -> Bool {
        guard let output = ProcessOutputReader.read(executable: "/usr/bin/pmset", arguments: ["-g", "batt"])?.lowercased() else {
            return false
        }
        return output.contains("charging") || output.contains("charged")
    }

    public func isLidClosed() -> Bool {
        guard let output = ProcessOutputReader.read(executable: "/usr/sbin/ioreg", arguments: ["-r", "-k", "AppleClamshellState", "-d", "4"])?.lowercased() else {
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
}
