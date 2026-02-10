import Foundation

protocol SleepSettingsControlling {
    func setDisableSleep(_ disabled: Bool) throws
}

enum SleepControllerError: Error, Equatable {
    case commandFailed(Int32)
}

struct SystemSleepSettingsController: SleepSettingsControlling {
    func setDisableSleep(_ disabled: Bool) throws {
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
