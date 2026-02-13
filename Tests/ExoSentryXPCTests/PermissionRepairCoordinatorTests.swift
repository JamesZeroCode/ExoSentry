import ExoSentryCore
import ExoSentryXPC
import XCTest

private final class PrivilegedClientSpy: PrivilegedCommanding, @unchecked Sendable {
    var state: PrivilegeState
    var repaired = false

    init(state: PrivilegeState) {
        self.state = state
    }

    func setDisableSleep(_ disabled: Bool) throws {}

    func restartWiFi() throws {}

    func setStaticIP(service: String, ip: String, subnet: String, router: String) throws {}

    func setV6LinkLocal(service: String) throws {}

    func repairPrivileges() throws {
        repaired = true
        state = .healthy
    }

    func currentPrivilegeState() -> PrivilegeState {
        state
    }

    func currentSOCTemperature() -> Double? {
        nil
    }
}

final class PermissionRepairCoordinatorTests: XCTestCase {
    func testLostPermissionSetsWarningState() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let client = PrivilegedClientSpy(state: .lost)
        let coordinator = PermissionRepairCoordinator(privilegedClient: client, stateStore: store)

        await coordinator.refreshWarningState()

        let state = await store.permissionWarningState()
        XCTAssertEqual(state, .warning)
    }

    func testRepairClearsWarningState() async throws {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let client = PrivilegedClientSpy(state: .lost)
        let coordinator = PermissionRepairCoordinator(privilegedClient: client, stateStore: store)

        try await coordinator.repairIfNeeded()

        let state = await store.permissionWarningState()
        XCTAssertEqual(state, .none)
        XCTAssertTrue(client.repaired)
    }
}
