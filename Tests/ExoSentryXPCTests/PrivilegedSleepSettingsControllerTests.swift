import ExoSentryCore
import ExoSentryXPC
import XCTest

private final class PrivilegedClientSleepSpy: PrivilegedCommanding, @unchecked Sendable {
    var values: [Bool] = []

    func setDisableSleep(_ disabled: Bool) throws {
        values.append(disabled)
    }

    func restartWiFi() throws {}

    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws {}

    func setV6LinkLocal(service: String) throws {}

    func repairPrivileges() throws {}

    func currentPrivilegeState() -> PrivilegeState {
        .healthy
    }

    func currentSOCTemperature() -> Double? {
        nil
    }
}

final class PrivilegedSleepSettingsControllerTests: XCTestCase {
    func testForwardsSleepToggleToPrivilegedClient() throws {
        let client = PrivilegedClientSleepSpy()
        let controller = PrivilegedSleepSettingsController(privilegedClient: client)

        try controller.setDisableSleep(true)
        try controller.setDisableSleep(false)

        XCTAssertEqual(client.values, [true, false])
    }
}
