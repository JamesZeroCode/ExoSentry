import XCTest
@testable import ExoSentryCore

final class AppStateStoreTests: XCTestCase {
    func testSnapshotReflectsSingleSourceOfTruth() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        await store.updateGuardStatus(.active)
        await store.updateTargetProcess("exo", running: true)
        await store.updateNetworkState(.ok)
        await store.updateTemperature(66.3)
        await store.updateCharging(true)
        await store.updateLidClosed(true)

        let payload = await store.snapshotStatus(lastUpdated: "2026-02-09T12:00:00+08:00")

        XCTAssertEqual(payload.status, .active)
        XCTAssertEqual(payload.mode, .cluster)
        XCTAssertEqual(payload.tempC, 66.3)
        XCTAssertEqual(payload.targetProcess, "exo")
        XCTAssertTrue(payload.targetProcessRunning)
    }

    func testPermissionWarningForcesDegradedStatus() async {
        let store = AppStateStore(initialMode: .standard, targetProcess: "exo")
        await store.updateGuardStatus(.active)
        await store.updatePermissionWarning(.warning)

        let payload = await store.snapshotStatus(lastUpdated: "2026-02-09T12:00:00+08:00")

        XCTAssertEqual(payload.status, .degraded)
    }
}
