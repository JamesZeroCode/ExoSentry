import XCTest
@testable import ExoSentryCore

final class StatusPayloadTests: XCTestCase {
    func testEncodesSnakeCaseSchemaFields() throws {
        let payload = StatusPayload(
            status: .active,
            mode: .cluster,
            tempC: 65.2,
            isCharging: true,
            lidClosed: true,
            targetProcess: "exo",
            targetProcessRunning: true,
            networkState: .ok,
            lastUpdated: "2026-02-09T12:00:00+08:00"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["schema_version"] as? String, "1.0")
        XCTAssertEqual(object?["status"] as? String, "active")
        XCTAssertEqual(object?["mode"] as? String, "cluster")
        XCTAssertEqual(object?["temp_c"] as? Double, 65.2)
        XCTAssertEqual(object?["is_charging"] as? Bool, true)
        XCTAssertEqual(object?["lid_closed"] as? Bool, true)
        XCTAssertEqual(object?["target_process"] as? String, "exo")
        XCTAssertEqual(object?["target_process_running"] as? Bool, true)
        XCTAssertEqual(object?["network_state"] as? String, "ok")
        XCTAssertEqual(object?["last_updated"] as? String, "2026-02-09T12:00:00+08:00")
    }

    func testSupportsNullTemperature() throws {
        let payload = StatusPayload(
            status: .paused,
            mode: .standard,
            tempC: nil,
            isCharging: false,
            lidClosed: false,
            targetProcess: "exo",
            targetProcessRunning: false,
            networkState: .wanLost,
            lastUpdated: "2026-02-09T12:00:00+08:00"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertTrue(object?.keys.contains("temp_c") == true)
        XCTAssertTrue(object?["temp_c"] is NSNull)
    }
}
