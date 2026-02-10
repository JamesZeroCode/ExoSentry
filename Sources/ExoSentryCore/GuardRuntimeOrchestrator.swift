import Foundation

public struct RuntimeDependencies: Sendable {
    public let processProvider: ProcessSnapshotProviding
    public let networkProbe: NetworkProbing
    public let temperatureProvider: TemperatureProviding
    public let powerManager: PowerAssertionManaging
    public let sleepCoordinator: GuardCoordinator
    public let processController: ProcessControlling
    public let appNapActivityManager: AppNapActivityManaging

    public init(
        processProvider: ProcessSnapshotProviding,
        networkProbe: NetworkProbing,
        temperatureProvider: TemperatureProviding,
        powerManager: PowerAssertionManaging,
        sleepCoordinator: GuardCoordinator,
        processController: ProcessControlling = SystemProcessController(),
        appNapActivityManager: AppNapActivityManaging = ProcessInfoAppNapActivityManager()
    ) {
        self.processProvider = processProvider
        self.networkProbe = networkProbe
        self.temperatureProvider = temperatureProvider
        self.powerManager = powerManager
        self.sleepCoordinator = sleepCoordinator
        self.processController = processController
        self.appNapActivityManager = appNapActivityManager
    }
}

public struct RuntimeCycleResult: Sendable {
    public let connectivityAction: ConnectivityAction?
    public let thermalAction: ThermalAction?

    public init(connectivityAction: ConnectivityAction?, thermalAction: ThermalAction?) {
        self.connectivityAction = connectivityAction
        self.thermalAction = thermalAction
    }
}

public final class GuardRuntimeOrchestrator: @unchecked Sendable {
    private let store: AppStateStore
    private let matcher: ProcessMatcher
    private let connectivityTracker: ConnectivityPolicyTracker
    private var thermalController: ThermalProtectionController
    private let deps: RuntimeDependencies
    private var mode: OperatingMode
    private var targets: [String]
    private var lastAutoRestartAttemptAt: Date?
    private let autoRestartCooldownSeconds: TimeInterval = 15

    public init(
        store: AppStateStore,
        matcher: ProcessMatcher = ProcessMatcher(),
        connectivityTracker: ConnectivityPolicyTracker = ConnectivityPolicyTracker(),
        thermalController: ThermalProtectionController = ThermalProtectionController(),
        dependencies: RuntimeDependencies,
        mode: OperatingMode,
        targets: [String]
    ) {
        self.store = store
        self.matcher = matcher
        self.connectivityTracker = connectivityTracker
        self.thermalController = thermalController
        self.deps = dependencies
        self.mode = mode
        self.targets = targets
    }

    public func updateMode(_ mode: OperatingMode) async {
        self.mode = mode
        await store.updateMode(mode)
    }

    public func updateTargets(_ targets: [String]) {
        self.targets = targets
    }

    public func runCycle() async -> RuntimeCycleResult {
        let runningNames = (try? deps.processProvider.runningProcessNames()) ?? []
        let shouldActivate = matcher.shouldActivateGuard(configuredTargets: targets, runningProcessNames: runningNames)
        let target = targets.first ?? ""
        await store.updateTargetProcess(target, running: shouldActivate)

        if shouldActivate {
            _ = try? deps.powerManager.activate()
            _ = try? deps.sleepCoordinator.activate(mode: mode)
            deps.appNapActivityManager.beginActivity(reason: "Protect target process: \(target)")
            await store.updateGuardStatus(.active)
        } else {
            if shouldAttemptAutoRestart(target: target) {
                _ = try? deps.processController.launchProcess(named: target)
                lastAutoRestartAttemptAt = Date()
            }
            deps.powerManager.deactivate()
            _ = try? deps.sleepCoordinator.deactivate()
            deps.appNapActivityManager.endActivity()
            await store.updateGuardStatus(.paused)
        }

        var connectivityAction: ConnectivityAction?

        if let probe = try? deps.networkProbe.probe() {
            let action = connectivityTracker.evaluate(probe)
            connectivityAction = action
            await store.updateNetworkState(probe.networkState)
            if case .alert = action {
                await store.updateGuardStatus(.degraded)
            }
        }

        let temperature = deps.temperatureProvider.currentTemperatureC()
        await store.updateTemperature(temperature)
        var thermalAction: ThermalAction?
        if let temp = temperature {
            let action = thermalController.record(temperatureC: temp)
            thermalAction = action
            if action == .tripped {
                _ = try? deps.processController.terminateProcess(named: target)
                await store.updateGuardStatus(.overheatTrip)
            }
        }

        return RuntimeCycleResult(connectivityAction: connectivityAction, thermalAction: thermalAction)
    }

    public func confirmThermalRecovery() async {
        if thermalController.confirmRecovery() == .recovered {
            await store.updateGuardStatus(.active)
        }
    }

    public func updateThermalPolicy(_ policy: ThermalPolicy) {
        thermalController = ThermalProtectionController(policy: policy)
    }

    private func shouldAttemptAutoRestart(target: String) -> Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard let lastAttempt = lastAutoRestartAttemptAt else {
            return true
        }
        return Date().timeIntervalSince(lastAttempt) >= autoRestartCooldownSeconds
    }
}
