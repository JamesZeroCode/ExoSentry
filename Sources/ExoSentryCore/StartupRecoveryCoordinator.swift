import Foundation

public final class StartupRecoveryCoordinator: @unchecked Sendable {
    private let guardCoordinator: GuardCoordinator
    private let logger: Logging

    public init(guardCoordinator: GuardCoordinator, logger: Logging) {
        self.guardCoordinator = guardCoordinator
        self.logger = logger
    }

    public func recoverOnLaunch() {
        do {
            try guardCoordinator.recoverResidualState()
            logger.log(.info, operation: "startup.recover", message: "residual sleep state cleared", metadata: [:])
        } catch {
            logger.log(.error, operation: "startup.recover", message: "failed to clear residual sleep state", metadata: ["error": error.localizedDescription])
        }
    }
}
