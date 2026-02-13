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

private final class ProcessControllerSpy: ProcessControlling, @unchecked Sendable {
    var launchProcessCalls: [String] = []
    var launchCommandCalls: [String] = []
    var terminateCalls: [String] = []
    var forceTerminateCalls: [String] = []

    func terminateProcess(named: String) throws {
        terminateCalls.append(named)
    }
    func forceTerminateProcess(named: String) throws {
        forceTerminateCalls.append(named)
    }
    func launchProcess(named: String) throws {
        launchProcessCalls.append(named)
    }
    func launchCommand(_ command: String) throws {
        launchCommandCalls.append(command)
    }
}

private final class AppNapNoop: AppNapActivityManaging {
    func beginActivity(reason: String) {}
    func endActivity() {}
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

        _ = await orchestrator.runCycle()
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

        _ = await orchestrator.runCycle()
        let payload = await store.snapshotStatus(lastUpdated: "2026-02-09T12:00:00+08:00")

        XCTAssertEqual(payload.status, .overheatTrip)
    }

    // MARK: - Auto-restart tests

    func testAutoRestartAttemptsLaunchWhenTargetNotRunning() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let power = PowerManagerSpy()
        let processController = ProcessControllerSpy()
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: []),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: true, internetReachable: true)),
            temperatureProvider: TemperatureProviderStub(value: 70),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop()),
            processController: processController,
            appNapActivityManager: AppNapNoop()
        )
        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            dependencies: deps,
            mode: .cluster,
            targets: ["exo"],
            autoRestartEnabled: true,
            launchCommand: "echo test"
        )

        let result = await orchestrator.runCycle()

        XCTAssertTrue(processController.launchCommandCalls.contains("echo test"),
                       "Expected launchCommand to be called with 'echo test'")
        XCTAssertNotNil(result.restartAttempt)
        XCTAssertEqual(result.restartAttempt?.kind, .normal)
    }

    func testAutoRestartRespectsEmptyTarget() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "")
        let power = PowerManagerSpy()
        let processController = ProcessControllerSpy()
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: []),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: true, internetReachable: true)),
            temperatureProvider: TemperatureProviderStub(value: 70),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop()),
            processController: processController,
            appNapActivityManager: AppNapNoop()
        )
        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            dependencies: deps,
            mode: .cluster,
            targets: [""],
            autoRestartEnabled: true,
            launchCommand: "echo test"
        )

        let result = await orchestrator.runCycle()

        XCTAssertNil(result.restartAttempt,
                     "Should not attempt restart when target is empty")
        XCTAssertTrue(processController.launchCommandCalls.isEmpty)
        XCTAssertTrue(processController.launchProcessCalls.isEmpty)
    }

    func testAutoRestartUsesLaunchProcessWhenCommandEmpty() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "myprocess")
        let power = PowerManagerSpy()
        let processController = ProcessControllerSpy()
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: []),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: true, internetReachable: true)),
            temperatureProvider: TemperatureProviderStub(value: 70),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop()),
            processController: processController,
            appNapActivityManager: AppNapNoop()
        )
        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            dependencies: deps,
            mode: .cluster,
            targets: ["myprocess"],
            autoRestartEnabled: true,
            launchCommand: ""
        )

        let result = await orchestrator.runCycle()

        XCTAssertTrue(processController.launchProcessCalls.contains("myprocess"),
                       "Expected launchProcess to be called with 'myprocess' when command is empty")
        XCTAssertTrue(processController.launchCommandCalls.isEmpty,
                       "launchCommand should not be called when command is empty")
        XCTAssertNotNil(result.restartAttempt)
        XCTAssertEqual(result.restartAttempt?.kind, .normal)
    }

    // MARK: - Network degraded test

    func testNetworkDegradedSetsStatus() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let power = PowerManagerSpy()
        // Use a policy with failureThreshold=1 and maxRetries=0 so a single failure triggers alert
        let connectivityTracker = ConnectivityPolicyTracker(
            policy: ConnectivityPolicy(failureThreshold: 1, maxRetries: 0)
        )
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: ["exo"]),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: false, internetReachable: false)),
            temperatureProvider: TemperatureProviderStub(value: 70),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop()),
            appNapActivityManager: AppNapNoop()
        )
        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            connectivityTracker: connectivityTracker,
            dependencies: deps,
            mode: .cluster,
            targets: ["exo"]
        )

        let result = await orchestrator.runCycle()
        let payload = await store.snapshotStatus(lastUpdated: "2026-02-14T12:00:00+08:00")

        if case .alert = result.connectivityAction {
            // expected
        } else {
            XCTFail("Expected connectivity action to be .alert, got \(String(describing: result.connectivityAction))")
        }
        XCTAssertEqual(payload.status, .degraded,
                       "Guard status should be degraded when network is in alert state")
    }

    // MARK: - Deactivation test

    func testRunCycleDeactivatesWhenTargetNotRunning() async {
        let store = AppStateStore(initialMode: .cluster, targetProcess: "exo")
        let power = PowerManagerSpy()
        let deps = RuntimeDependencies(
            processProvider: ProcessProviderStub(names: []),
            networkProbe: NetworkProbeStub(snapshot: ProbeSnapshot(gatewayReachable: true, internetReachable: true)),
            temperatureProvider: TemperatureProviderStub(value: 70),
            powerManager: power,
            sleepCoordinator: GuardCoordinator(sleepController: SleepControllerNoop()),
            appNapActivityManager: AppNapNoop()
        )
        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            dependencies: deps,
            mode: .cluster,
            targets: ["exo"],
            autoRestartEnabled: false
        )

        _ = await orchestrator.runCycle()
        let payload = await store.snapshotStatus(lastUpdated: "2026-02-14T12:00:00+08:00")

        XCTAssertGreaterThanOrEqual(power.deactivateCount, 1,
                                     "Power should be deactivated when target is not running")
        XCTAssertEqual(payload.status, .paused,
                       "Guard status should be paused when target is not running")
    }
}
