import Foundation
import XCTest
@testable import ExoSentryCore

final class ThunderboltIPConfigTests: XCTestCase {

    // MARK: - defaultConfigs

    func testDefaultConfigsHasFourEntries() {
        XCTAssertEqual(ThunderboltIPConfig.defaultConfigs.count, 4)
    }

    func testDefaultConfigsIdEqualsService() {
        for config in ThunderboltIPConfig.defaultConfigs {
            XCTAssertEqual(config.id, config.service)
        }
    }

    // MARK: - Init defaults

    func testInitDefaultSubnetIs255() {
        let config = ThunderboltIPConfig(service: "Test", ip: "10.0.0.1")
        XCTAssertEqual(config.subnet, "255.255.255.0")
    }

    func testInitDefaultRouterIsEmpty() {
        let config = ThunderboltIPConfig(service: "Test", ip: "10.0.0.1")
        XCTAssertEqual(config.router, "")
    }

    func testInitDefaultEnabledIsTrue() {
        let config = ThunderboltIPConfig(service: "Test", ip: "10.0.0.1")
        XCTAssertTrue(config.enabled)
    }

    func testInitWithCustomValues() {
        let config = ThunderboltIPConfig(
            service: "Custom",
            ip: "192.168.1.100",
            subnet: "255.255.0.0",
            router: "192.168.1.1",
            enabled: false
        )
        XCTAssertEqual(config.service, "Custom")
        XCTAssertEqual(config.ip, "192.168.1.100")
        XCTAssertEqual(config.subnet, "255.255.0.0")
        XCTAssertEqual(config.router, "192.168.1.1")
        XCTAssertFalse(config.enabled)
    }

    // MARK: - JSON round-trip

    func testJSONRoundTrip() throws {
        let original = ThunderboltIPConfig(
            service: "EXO Thunderbolt 1",
            ip: "10.0.0.1",
            subnet: "255.255.255.0",
            router: "10.0.0.254",
            enabled: true
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ThunderboltIPConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testJSONRoundTripForDefaultConfigs() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(ThunderboltIPConfig.defaultConfigs)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ThunderboltIPConfig].self, from: data)

        XCTAssertEqual(decoded, ThunderboltIPConfig.defaultConfigs)
    }

    // MARK: - Equatable

    func testEqualConfigsAreEqual() {
        let a = ThunderboltIPConfig(service: "S1", ip: "10.0.0.1")
        let b = ThunderboltIPConfig(service: "S1", ip: "10.0.0.1")
        XCTAssertEqual(a, b)
    }

    func testDifferentServiceNotEqual() {
        let a = ThunderboltIPConfig(service: "S1", ip: "10.0.0.1")
        let b = ThunderboltIPConfig(service: "S2", ip: "10.0.0.1")
        XCTAssertNotEqual(a, b)
    }

    func testDifferentIPNotEqual() {
        let a = ThunderboltIPConfig(service: "S1", ip: "10.0.0.1")
        let b = ThunderboltIPConfig(service: "S1", ip: "10.0.0.2")
        XCTAssertNotEqual(a, b)
    }

    func testDifferentEnabledNotEqual() {
        let a = ThunderboltIPConfig(service: "S1", ip: "10.0.0.1", enabled: true)
        let b = ThunderboltIPConfig(service: "S1", ip: "10.0.0.1", enabled: false)
        XCTAssertNotEqual(a, b)
    }
}
