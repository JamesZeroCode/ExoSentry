import Foundation

public enum SleepControllerError: Error, Equatable {
    case commandFailed(Int32)
}

public struct SystemSleepSettingsController: SleepSettingsControlling {
    public init() {}

    public func setDisableSleep(_ disabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SleepControllerError.commandFailed(process.terminationStatus)
        }
    }
}
