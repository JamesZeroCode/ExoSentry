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

private struct NetworkIPControllerStub: NetworkIPControlling {
    let shouldThrowSnapshot: Bool
    let snapshot: (configuration: String, ipAddress: String?)

    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws {}

    func setV6LinkLocal(service: String) throws {}

    func currentIPv4Snapshot(service: String) throws -> (configuration: String, ipAddress: String?) {
        if shouldThrowSnapshot {
            throw NetworkIPControlError.commandFailed(command: "networksetup -getinfo", code: 1, details: "probe failed")
        }
        return snapshot
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

    func testCurrentServiceIPv4SnapshotReturnsConfigurationAndIP() {
        let service = HelperService(
            sleepController: SleepControllerStub(shouldThrow: false),
            wifiController: WiFiControllerStub(shouldThrow: false),
            networkIPController: NetworkIPControllerStub(shouldThrowSnapshot: false, snapshot: (configuration: "selfAssigned", ipAddress: "169.254.10.2")),
            initialState: .healthy
        )

        let snapshot = invokeCurrentServiceIPv4Snapshot(service, serviceName: "EXO Thunderbolt 2")

        XCTAssertEqual(snapshot.configuration, "selfAssigned")
        XCTAssertEqual(snapshot.value, "169.254.10.2")
    }

    func testCurrentServiceIPv4SnapshotReturnsErrorPayloadWhenControllerFails() {
        let service = HelperService(
            sleepController: SleepControllerStub(shouldThrow: false),
            wifiController: WiFiControllerStub(shouldThrow: false),
            networkIPController: NetworkIPControllerStub(shouldThrowSnapshot: true, snapshot: (configuration: "unknown", ipAddress: nil)),
            initialState: .healthy
        )

        let snapshot = invokeCurrentServiceIPv4Snapshot(service, serviceName: "EXO Thunderbolt 2")

        XCTAssertEqual(snapshot.configuration, "error")
        XCTAssertTrue(snapshot.value.contains("networksetup -getinfo"))
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

    private func invokeCurrentServiceIPv4Snapshot(_ service: HelperService, serviceName: String) -> (configuration: String, value: String) {
        let expectation = expectation(description: "currentServiceIPv4Snapshot callback")
        var configuration = ""
        var value = ""
        service.currentServiceIPv4Snapshot(serviceName as NSString) { config, payload in
            configuration = String(config)
            value = String(payload ?? "")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return (configuration: configuration, value: value)
    }
}
