import XCTest
@testable import ExoSentryCore

private final class PowerAssertionSystemSpy: PowerAssertionSystem, @unchecked Sendable {
    var createQueue: [IOPMAssertionID?] = [11, 22]
    var released: [IOPMAssertionID] = []

    func createAssertion(type: CFString, name: CFString) -> IOPMAssertionID? {
        if createQueue.isEmpty {
            return nil
        }
        return createQueue.removeFirst()
    }

    func releaseAssertion(id: IOPMAssertionID) {
        released.append(id)
    }
}

final class PowerAssertionManagerTests: XCTestCase {
    func testActivateAndDeactivate() throws {
        let spy = PowerAssertionSystemSpy()
        let manager = PowerAssertionManager(system: spy)

        try manager.activate()
        XCTAssertTrue(manager.isActive)

        manager.deactivate()
        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(spy.released, [11, 22])
    }

    func testActivateRollsBackWhenSecondAssertionFails() {
        let spy = PowerAssertionSystemSpy()
        spy.createQueue = [11, nil]
        let manager = PowerAssertionManager(system: spy)

        XCTAssertThrowsError(try manager.activate())
        XCTAssertEqual(spy.released, [11])
        XCTAssertFalse(manager.isActive)
    }
}
