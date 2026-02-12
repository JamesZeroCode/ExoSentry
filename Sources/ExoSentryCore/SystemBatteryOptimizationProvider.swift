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
        guard let output = ProcessOutputReader.read(executable: "/usr/bin/pmset", arguments: ["-g", "batt"])?.lowercased() else {
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
}
