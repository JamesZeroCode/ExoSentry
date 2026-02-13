import XCTest
@testable import ExoSentryHelper

private struct SleepControllerStub: SleepSettingsControlling {
    let shouldThrow: Bool

    func setDisableSleep(_ disabled: Bool) throws {
        if shouldThrow {
            throw SleepControllerError.commandFailed(1)
        }
    }
}

private struct WiFiControllerStub: WiFiControlling {
    let shouldThrow: Bool

    func restartWiFi() throws {
        if shouldThrow {
            throw WiFiControlError.commandFailed(1)
        }
    }
}

final class HelperServicePrivilegeStateTests: XCTestCase {
    func testSetDisableSleepFailureMarksPrivilegeLost() {
        let service = HelperService(
            sleepController: SleepControllerStub(shouldThrow: true),
            wifiController: WiFiControllerStub(shouldThrow: false),
            initialState: .healthy
        )

        let error = invokeSetDisableSleep(service, disabled: true)

        XCTAssertNotNil(error)
        XCTAssertEqual(readState(service), .lost)
    }

    func testRepairPrivilegesRestoresHealthyState() {
        let service = HelperService(
            sleepController: SleepControllerStub(shouldThrow: true),
            wifiController: WiFiControllerStub(shouldThrow: false),
            initialState: .healthy
        )

        _ = invokeSetDisableSleep(service, disabled: true)
        XCTAssertEqual(readState(service), .lost)

        let repairError = invokeRepairPrivileges(service)
        XCTAssertNil(repairError)
        XCTAssertEqual(readState(service), .healthy)
    }

    private func invokeSetDisableSleep(_ service: HelperService, disabled: Bool) -> NSString? {
        let expectation = expectation(description: "setDisableSleep callback")
        var callbackError: NSString?
        service.setDisableSleep(disabled) { error in
            callbackError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return callbackError
    }

    private func invokeRepairPrivileges(_ service: HelperService) -> NSString? {
        let expectation = expectation(description: "repairPrivileges callback")
        var callbackError: NSString?
        service.repairPrivileges { error in
            callbackError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return callbackError
    }

    private func readState(_ service: HelperService) -> PrivilegeState {
        let expectation = expectation(description: "currentPrivilegeState callback")
        var raw: String = ""
        service.currentPrivilegeState { value in
            raw = String(value)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return PrivilegeState(rawValue: raw) ?? .lost
    }
}
