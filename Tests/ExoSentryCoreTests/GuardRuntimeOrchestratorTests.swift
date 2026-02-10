import XCTest
@testable import ExoSentryCore

private struct ProcessProviderStub: ProcessSnapshotProviding {
    let names: [String]
    func runningProcessNames() throws -> [String] { names }
}

private struct NetworkProbeStub: NetworkProbing {
    let snapshot: ProbeSnapshot
    func probe() throws -> ProbeSnapshot { snapshot }
}

private struct TemperatureProviderStub: TemperatureProviding {
    let value: Double?
    func currentTemperatureC() -> Double? { value }
}

private final class PowerManagerSpy: PowerAssertionManaging, @unchecked Sendable {
    var isActive = false
    var activateCount = 0
    var deactivateCount = 0

    func activate() throws {
        activateCount += 1
        isActive = true
    }

    func deactivate() {
        deactivateCount += 1
        isActive = false
    }
}

private final class SleepControllerNoop: SleepSettingsControlling, @unchecked Sendable {
    func setDisableSleep(_ disabled: Bool) throws {}
}

final class GuardRuntimeOrchestratorTests: XCTestCase {
    func testRunCycleActivatesWhenTargetProcessRunning() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let power = PowerManagerSpy()
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: ["exo"]),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: true, internetReachable: true)),
            temperatureProvider: TemperatureProviderStub(value: 70),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop())
        )
        let orchestrator = GuardRuntimeOrchestrator(store: store, dependencies: deps, mode: .cluster, targets: ["exo"])

        await orchestrator.runCycle()
        let payload = await store.snapshotStatus(lastUpdated: "2026-02-09T12:00:00+08:00")

        XCTAssertEqual(payload.status, .active)
        XCTAssertEqual(power.activateCount, 1)
        XCTAssertTrue(payload.targetProcessRunning)
    }

    func testRunCycleTripsOverheat() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let power = PowerManagerSpy()
        let thermal = ThermalProtectionController(
            policy: ThermalPolicy(sampleIntervalSeconds: 5, tripTemperatureC: 95, tripDurationSeconds: 5, recoverTemperatureC: 85, recoverDurationSeconds: 10)
        )
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: ["exo"]),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: true, internetReachable: true)),
            temperatureProvider: TemperatureProviderStub(value: 96),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop())
        )
        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            thermalController: thermal,
            dependencies: deps,
            mode: .cluster,
            targets: ["exo"]
        )

        await orchestrator.runCycle()
        let payload = await store.snapshotStatus(lastUpdated: "2026-02-09T12:00:00+08:00")

        XCTAssertEqual(payload.status, .overheatTrip)
    }
}
