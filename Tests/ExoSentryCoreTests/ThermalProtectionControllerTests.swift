import XCTest
@testable import ExoSentryCore

final class ThermalProtectionControllerTests: XCTestCase {
    func testTripsAfterConfiguredHighTemperatureWindow() {
        let policy = ThermalPolicy(sampleIntervalSeconds: 5, tripTemperatureC: 95, tripDurationSeconds: 60, recoverTemperatureC: 85, recoverDurationSeconds: 120)
        let controller = ThermalProtectionController(policy: policy)

        var action: ThermalAction = .none
        for _ in 0..<12 {
            action = controller.record(temperatureC: 96)
        }

        XCTAssertEqual(action, .tripped)
    }

    func testRecoveryRequiresHysteresisAndManualConfirmation() {
        let policy = ThermalPolicy(sampleIntervalSeconds: 5, tripTemperatureC: 95, tripDurationSeconds: 10, recoverTemperatureC: 85, recoverDurationSeconds: 20)
        let controller = ThermalProtectionController(policy: policy)

        _ = controller.record(temperatureC: 96)
        _ = controller.record(temperatureC: 96)

        XCTAssertEqual(controller.record(temperatureC: 84), .none)
        XCTAssertEqual(controller.record(temperatureC: 84), .none)
        XCTAssertEqual(controller.record(temperatureC: 84), .none)
        XCTAssertEqual(controller.record(temperatureC: 84), .recoveryReady)
        XCTAssertEqual(controller.confirmRecovery(), .recovered)
    }
}
