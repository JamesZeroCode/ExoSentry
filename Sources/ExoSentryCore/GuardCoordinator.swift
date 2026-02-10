import Foundation

public protocol SleepSettingsControlling: Sendable {
    func setDisableSleep(_ disabled: Bool) throws
}

public enum GuardCoordinatorError: Error, Equatable {
    case clamshellToggleFailed
}

public final class GuardCoordinator: @unchecked Sendable {
    private let sleepController: SleepSettingsControlling
    private var clamshellApplied = false

    public init(sleepController: SleepSettingsControlling) {
        self.sleepController = sleepController
    }

    public func activate(mode: OperatingMode) throws {
        let behavior = ModeBehavior.forMode(mode)
        guard behavior.allowClamshell else {
            return
        }

        do {
            try sleepController.setDisableSleep(true)
            clamshellApplied = true
        } catch {
            throw GuardCoordinatorError.clamshellToggleFailed
        }
    }

    public func deactivate() throws {
        guard clamshellApplied else {
            return
        }

        do {
            try sleepController.setDisableSleep(false)
            clamshellApplied = false
        } catch {
            throw GuardCoordinatorError.clamshellToggleFailed
        }
    }

    public func recoverResidualState() throws {
        do {
            try sleepController.setDisableSleep(false)
            clamshellApplied = false
        } catch {
            throw GuardCoordinatorError.clamshellToggleFailed
        }
    }
}
