import Foundation

public enum BatteryOptimizationState: Sendable {
    case enabled
    case disabled
    case unknown
}

public protocol BatteryOptimizationProviding: Sendable {
    func optimizedChargingState() -> BatteryOptimizationState
}

public struct SystemBatteryOptimizationProvider: BatteryOptimizationProviding {
    public init() {}

    public func optimizedChargingState() -> BatteryOptimizationState {
        guard let output = runProcess("/usr/bin/pmset", arguments: ["-g", "batt"])?.lowercased() else {
            return .unknown
        }
        if output.contains("optimized battery charging: enabled") {
            return .enabled
        }
        if output.contains("optimized battery charging: disabled") {
            return .disabled
        }
        return .unknown
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
