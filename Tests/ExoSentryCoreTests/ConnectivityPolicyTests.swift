import XCTest
@testable import ExoSentryCore

final class ConnectivityPolicyTests: XCTestCase {
    func testHealthySnapshotResetsCounters() {
        let tracker = ConnectivityPolicyTracker()

        _ = tracker.evaluate(ProbeSnapshot(gatewayReachable: false, internetReachable: false))
        let action = tracker.evaluate(ProbeSnapshot(gatewayReachable: true, internetReachable: true))

        XCTAssertEqual(action, .healthy)
    }

    func testRetriesAfterFailureThresholdAndThenAlerts() {
        let tracker = ConnectivityPolicyTracker(policy: ConnectivityPolicy(failureThreshold: 3, maxRetries: 3))
        let fail = ProbeSnapshot(gatewayReachable: true, internetReachable: false)

        XCTAssertEqual(tracker.evaluate(fail), .healthy)
        XCTAssertEqual(tracker.evaluate(fail), .healthy)
        XCTAssertEqual(tracker.evaluate(fail), .retry(.wanLost, 1))
        XCTAssertEqual(tracker.evaluate(fail), .retry(.wanLost, 2))
        XCTAssertEqual(tracker.evaluate(fail), .retry(.wanLost, 3))
        XCTAssertEqual(tracker.evaluate(fail), .alert(.wanLost))
    }

    func testSnapshotStateMapping() {
        XCTAssertEqual(ProbeSnapshot(gatewayReachable: true, internetReachable: true).networkState, .ok)
        XCTAssertEqual(ProbeSnapshot(gatewayReachable: false, internetReachable: true).networkState, .lanLost)
        XCTAssertEqual(ProbeSnapshot(gatewayReachable: true, internetReachable: false).networkState, .wanLost)
        XCTAssertEqual(ProbeSnapshot(gatewayReachable: false, internetReachable: false).networkState, .offline)
    }
}
