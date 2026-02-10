import XCTest
@testable import ExoSentryCore

final class LocalStatusServerTests: XCTestCase {
    func testReturnsStatusPayloadAtStatusEndpoint() async throws {
        let payload = StatusPayload(
            status: .active,
            mode: .cluster,
            tempC: 65,
            isCharging: true,
            lidClosed: false,
            targetProcess: "exo",
            targetProcessRunning: true,
            networkState: .ok,
            lastUpdated: "2026-02-09T12:00:00+08:00"
        )
        let server = LocalStatusServer(payloadProvider: { payload })
        try server.start(port: 19881)
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 150_000_000)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:19881/status"))
        let (data, response) = try await URLSession.shared.data(from: url)

        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(body?["schema_version"] as? String, "1.0")
        XCTAssertEqual(body?["target_process"] as? String, "exo")
    }
}
