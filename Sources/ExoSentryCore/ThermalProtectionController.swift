import Foundation

public struct ThermalPolicy: Equatable, Sendable {
    public let sampleIntervalSeconds: Int
    public let tripTemperatureC: Double
    public let tripDurationSeconds: Int
    public let recoverTemperatureC: Double
    public let recoverDurationSeconds: Int

    public init(
        sampleIntervalSeconds: Int = 5,
        tripTemperatureC: Double = 95,
        tripDurationSeconds: Int = 60,
        recoverTemperatureC: Double = 85,
        recoverDurationSeconds: Int = 120
    ) {
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.tripTemperatureC = tripTemperatureC
        self.tripDurationSeconds = tripDurationSeconds
        self.recoverTemperatureC = recoverTemperatureC
        self.recoverDurationSeconds = recoverDurationSeconds
    }

    public var tripSamplesRequired: Int {
        max(1, tripDurationSeconds / sampleIntervalSeconds)
    }

    public var recoverSamplesRequired: Int {
        max(1, recoverDurationSeconds / sampleIntervalSeconds)
    }
}

public enum ThermalAction: Equatable, Sendable {
    case none
    case tripped
    case recoveryReady
    case recovered
}

public final class ThermalProtectionController: @unchecked Sendable {
    private enum State {
        case normal
        case tripped
        case recoveryReady
    }

    private let policy: ThermalPolicy
    private let lock = NSLock()
    private var state: State = .normal
    private var highTempSamples = 0
    private var lowTempSamples = 0

    public init(policy: ThermalPolicy = ThermalPolicy()) {
        self.policy = policy
    }

    public func record(temperatureC: Double) -> ThermalAction {
        lock.lock()
        defer { lock.unlock() }
        
        switch state {
        case .normal:
            if temperatureC > policy.tripTemperatureC {
                highTempSamples += 1
                if highTempSamples >= policy.tripSamplesRequired {
                    state = .tripped
                    highTempSamples = 0
                    lowTempSamples = 0
                    return .tripped
                }
            } else {
                highTempSamples = 0
            }
            return .none
        case .tripped:
            if temperatureC < policy.recoverTemperatureC {
                lowTempSamples += 1
                if lowTempSamples >= policy.recoverSamplesRequired {
                    state = .recoveryReady
                    lowTempSamples = 0
                    return .recoveryReady
                }
            } else {
                lowTempSamples = 0
            }
            return .none
        case .recoveryReady:
            return .none
        }
    }

    public func confirmRecovery() -> ThermalAction {
        lock.lock()
        defer { lock.unlock() }
        
        guard state == .recoveryReady else {
            return .none
        }
        state = .normal
        highTempSamples = 0
        lowTempSamples = 0
        return .recovered
    }
}
