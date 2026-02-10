import XCTest
@testable import ExoSentryCore

private final class SleepControllerSpy: SleepSettingsControlling, @unchecked Sendable {
    var values: [Bool] = []
    var shouldThrow = false

    func setDisableSleep(_ disabled: Bool) throws {
        if shouldThrow {
            throw NSError(domain: "test", code: 1)
        }
        values.append(disabled)
    }
}

final class GuardCoordinatorTests: XCTestCase {
    func testActivateClusterAppliesClamshell() throws {
        let spy = SleepControllerSpy()
        let coordinator = GuardCoordinator(sleepController: spy)

        try coordinator.activate(mode: .cluster)

        XCTAssertEqual(spy.values, [true])
    }

    func testDeactivateRollsBackSleepSetting() throws {
        let spy = SleepControllerSpy()
        let coordinator = GuardCoordinator(sleepController: spy)

        try coordinator.activate(mode: .cluster)
        try coordinator.deactivate()

        XCTAssertEqual(spy.values, [true, false])
    }

    func testRecoverResidualStateForcesRollback() throws {
        let spy = SleepControllerSpy()
        let coordinator = GuardCoordinator(sleepController: spy)

        try coordinator.recoverResidualState()

        XCTAssertEqual(spy.values, [false])
    }

    func testActivateStandardDoesNotApplyClamshell() throws {
        let spy = SleepControllerSpy()
        let coordinator = GuardCoordinator(sleepController: spy)

        try coordinator.activate(mode: .standard)

        XCTAssertEqual(spy.values, [])
    }
}
