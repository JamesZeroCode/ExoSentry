import XCTest
@testable import ExoSentryCore

private final class RecoverySleepControllerSpy: SleepSettingsControlling, @unchecked Sendable {
    var values: [Bool] = []

    func setDisableSleep(_ disabled: Bool) throws {
        values.append(disabled)
    }
}

private final class LoggerSpy: Logging, @unchecked Sendable {
    var lines: [String] = []

    func log(_ level: LogLevel, operation: String, message: String, metadata: [String: String]) {
        lines.append("\(level.rawValue):\(operation):\(message)")
    }
}

final class StartupRecoveryCoordinatorTests: XCTestCase {
    func testRecoverOnLaunchCallsRollbackAndLogs() {
        let sleep = RecoverySleepControllerSpy()
        let guardCoordinator = GuardCoordinator(sleepController: sleep)
        let logger = LoggerSpy()
        let recovery = StartupRecoveryCoordinator(guardCoordinator: guardCoordinator, logger: logger)

        recovery.recoverOnLaunch()

        XCTAssertEqual(sleep.values, [false])
        XCTAssertTrue(logger.lines.contains { $0.contains("startup.recover") })
    }
}
