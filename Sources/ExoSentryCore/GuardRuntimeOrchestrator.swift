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
    public let restartAttempt: RestartAttemptInfo?

    public init(connectivityAction: ConnectivityAction?, thermalAction: ThermalAction?, restartAttempt: RestartAttemptInfo? = nil) {
        self.connectivityAction = connectivityAction
        self.thermalAction = thermalAction
        self.restartAttempt = restartAttempt
    }
}

public struct RestartAttemptInfo: Sendable {
    public enum Kind: Sendable {
        case normal
        case fullRestart
    }
    public let kind: Kind
    public let failureCount: Int
    public let error: String?
}

public final class GuardRuntimeOrchestrator: @unchecked Sendable {
    private let store: AppStateStore
    private let matcher: ProcessMatcher
    private let connectivityTracker: ConnectivityPolicyTracker
    private var thermalController: ThermalProtectionController
    private let deps: RuntimeDependencies
    private let logger: Logging?
    private let lock = NSLock()
    private var mode: OperatingMode
    private var targets: [String]
    private var autoRestartEnabled: Bool
    private var launchCommand: String
    private var lastAutoRestartAttemptAt: Date?
    private let autoRestartCooldownSeconds: TimeInterval = 15
    private var consecutiveRestartFailures: Int = 0
    private let maxRestartFailuresBeforeFullRestart: Int = 3
    private var lastFullRestartAttemptAt: Date?
    private let fullRestartCooldownSeconds: TimeInterval = 60

    public init(
        store: AppStateStore,
        matcher: ProcessMatcher = ProcessMatcher(),
        connectivityTracker: ConnectivityPolicyTracker = ConnectivityPolicyTracker(),
        thermalController: ThermalProtectionController = ThermalProtectionController(),
        dependencies: RuntimeDependencies,
        mode: OperatingMode,
        targets: [String],
        autoRestartEnabled: Bool = false,
        launchCommand: String = "",
        logger: Logging? = nil
    ) {
        self.store = store
        self.matcher = matcher
        self.connectivityTracker = connectivityTracker
        self.thermalController = thermalController
        self.deps = dependencies
        self.logger = logger
        self.mode = mode
        self.targets = targets
        self.autoRestartEnabled = autoRestartEnabled
        self.launchCommand = launchCommand
    }

    // MARK: - Synchronous lock helpers (avoid "lock unavailable from async context" warnings)

    private func lockedSetMode(_ newMode: OperatingMode) {
        lock.lock()
        defer { lock.unlock() }
        mode = newMode
    }

    private func lockedReadCycleState() -> (mode: OperatingMode, targets: [String], autoRestart: Bool, command: String) {
        lock.lock()
        defer { lock.unlock() }
        return (mode, targets, autoRestartEnabled, launchCommand)
    }

    private func lockedResetRestartFailures() {
        lock.lock()
        defer { lock.unlock() }
        consecutiveRestartFailures = 0
    }

    private func lockedReadRestartFailures() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return consecutiveRestartFailures
    }

    private func lockedRecordFullRestart() {
        lock.lock()
        defer { lock.unlock() }
        consecutiveRestartFailures = 0
        lastFullRestartAttemptAt = Date()
        lastAutoRestartAttemptAt = Date()
    }

    private func lockedRecordNormalRestart() -> Int {
        lock.lock()
        defer { lock.unlock() }
        consecutiveRestartFailures += 1
        lastAutoRestartAttemptAt = Date()
        return consecutiveRestartFailures
    }

    private func lockedRecordThermal(temperatureC: Double) -> ThermalAction {
        lock.lock()
        defer { lock.unlock() }
        return thermalController.record(temperatureC: temperatureC)
    }

    private func lockedConfirmThermalRecovery() -> ThermalAction {
        lock.lock()
        defer { lock.unlock() }
        return thermalController.confirmRecovery()
    }

    // MARK: - Public API

    public func updateMode(_ mode: OperatingMode) async {
        lockedSetMode(mode)
        await store.updateMode(mode)
    }

    public func updateTargets(_ targets: [String]) {
        lock.lock()
        defer { lock.unlock() }
        self.targets = targets
    }

    public func updateAutoRestart(enabled: Bool, command: String) {
        lock.lock()
        defer { lock.unlock() }
        self.autoRestartEnabled = enabled
        self.launchCommand = command
    }

    public func runCycle(probeNetwork: Bool = true) async -> RuntimeCycleResult {
        let state = lockedReadCycleState()
        let currentMode = state.mode
        let currentTargets = state.targets
        let currentAutoRestartEnabled = state.autoRestart
        let currentLaunchCommand = state.command
        let deps = self.deps
        var restartAttempt: RestartAttemptInfo?

        // Process snapshot — runs /bin/ps, blocks until exit
        let runningNames: [String] = await Self.offloadBlocking {
            (try? deps.processProvider.runningProcessNames()) ?? []
        }

        let shouldActivate = matcher.shouldActivateGuard(configuredTargets: currentTargets, runningProcessNames: runningNames)
        let normalizedTargets = currentTargets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let targetSummary = normalizedTargets.joined(separator: ", ")
        let runningLower = Set(runningNames.map { $0.lowercased() })
        let matchedTarget = normalizedTargets.first { runningLower.contains($0.lowercased()) }
        let primaryTarget = normalizedTargets.first ?? ""
        let actionTarget = matchedTarget ?? primaryTarget

        await store.updateTargetProcess(targetSummary, running: shouldActivate)

        if shouldActivate {
            lockedResetRestartFailures()
            // Guard activation — XPC call may block up to 15s when Helper not installed
            await Self.offloadBlocking {
                do {
                    try deps.powerManager.activate()
                } catch {
                    self.logger?.log(.error, operation: "guard.activate.power", message: "activation failed", metadata: ["error": error.localizedDescription])
                }
                do {
                    try deps.sleepCoordinator.activate(mode: currentMode)
                } catch {
                    self.logger?.log(.error, operation: "guard.activate.sleep", message: "activation failed", metadata: ["error": error.localizedDescription])
                }
            }
            deps.appNapActivityManager.beginActivity(reason: "Protect target process: \(actionTarget)")
            await store.updateGuardStatus(.active)
        } else {
            if currentAutoRestartEnabled && shouldAttemptAutoRestart(target: primaryTarget) {
                let currentFailures = lockedReadRestartFailures()
                if currentFailures >= maxRestartFailuresBeforeFullRestart
                    && shouldAttemptFullRestart() {
                    // Full restart: kill → reopen app → start service
                    logger?.log(.warning, operation: "autoRestart.full", message: "triggering full restart after \(currentFailures) failures", metadata: ["target": primaryTarget, "command": currentLaunchCommand])
                    let cmd = currentLaunchCommand
                    let appPath = Self.extractAppBundlePath(from: cmd)
                    let target = primaryTarget
                    await Self.offloadBlocking {
                        do {
                            try deps.processController.forceTerminateProcess(named: target)
                        } catch {
                            self.logger?.log(.error, operation: "autoRestart.full", message: "force terminate failed", metadata: ["target": target, "error": error.localizedDescription])
                        }
                    }
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        if Task.isCancelled {
                            return RuntimeCycleResult(connectivityAction: nil, thermalAction: nil, restartAttempt: nil)
                        }
                    }

                    if let appPath {
                        logger?.log(.info, operation: "autoRestart.full", message: "reopening app bundle", metadata: ["path": appPath])
                        await Self.offloadBlocking {
                            _ = try? deps.processController.launchCommand("open \"\(appPath)\"")
                        }
                        do {
                            try await Task.sleep(nanoseconds: 3_000_000_000)
                        } catch {
                            if Task.isCancelled {
                                return RuntimeCycleResult(connectivityAction: nil, thermalAction: nil, restartAttempt: nil)
                            }
                        }
                    }

                    let fullError: String? = await Self.offloadBlocking {
                        do {
                            if !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                try deps.processController.launchCommand(cmd)
                            } else {
                                try deps.processController.launchProcess(named: target)
                            }
                            return nil as String?
                        } catch {
                            return error.localizedDescription
                        }
                    }
                    if let err = fullError {
                        logger?.log(.error, operation: "autoRestart.full", message: "service launch failed", metadata: ["error": err, "command": cmd])
                    } else {
                        logger?.log(.info, operation: "autoRestart.full", message: "service launched", metadata: ["command": cmd])
                    }
                    restartAttempt = RestartAttemptInfo(kind: .fullRestart, failureCount: currentFailures, error: fullError)
                    lockedRecordFullRestart()
                } else {
                    // Normal restart attempt
                    let cmd = currentLaunchCommand
                    logger?.log(.info, operation: "autoRestart.normal", message: "attempt #\(currentFailures + 1)", metadata: ["target": primaryTarget, "command": cmd])
                    let normalError: String? = await Self.offloadBlocking {
                        do {
                            if !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                try deps.processController.launchCommand(cmd)
                            } else {
                                try deps.processController.launchProcess(named: primaryTarget)
                            }
                            return nil as String?
                        } catch {
                            return error.localizedDescription
                        }
                    }
                    if let err = normalError {
                        logger?.log(.error, operation: "autoRestart.normal", message: "launch failed", metadata: ["error": err, "command": cmd])
                    } else {
                        logger?.log(.info, operation: "autoRestart.normal", message: "command executed", metadata: ["command": cmd])
                    }
                    let updatedFailures = lockedRecordNormalRestart()
                    restartAttempt = RestartAttemptInfo(kind: .normal, failureCount: updatedFailures, error: normalError)
                }
            }
            // Guard deactivation — XPC call may block
            await Self.offloadBlocking {
                deps.powerManager.deactivate()
                do {
                    try deps.sleepCoordinator.deactivate()
                } catch {
                    self.logger?.log(.error, operation: "guard.deactivate.sleep", message: "deactivation failed", metadata: ["error": error.localizedDescription])
                }
            }
            deps.appNapActivityManager.endActivity()
            await store.updateGuardStatus(.paused)
        }

        var connectivityAction: ConnectivityAction?

        if probeNetwork {
            // Network probe — runs route + 2× ping, blocks until exit
            let probe: ProbeSnapshot? = await Self.offloadBlocking {
                do {
                    return try deps.networkProbe.probe()
                } catch {
                    self.logger?.log(.error, operation: "network.probe", message: "probe failed", metadata: ["error": error.localizedDescription])
                    return nil
                }
            }
            if let probe {
                let action = connectivityTracker.evaluate(probe)
                connectivityAction = action
                await store.updateNetworkState(probe.networkState)
                if case .alert = action {
                    await store.updateGuardStatus(.degraded)
                }
            }
        }

        // Temperature — runs powermetrics subprocess, blocks until exit
        let temperature: Double? = await Self.offloadBlocking {
            deps.temperatureProvider.currentTemperatureC()
        }
        await store.updateTemperature(temperature)
        var thermalAction: ThermalAction?
        if let temp = temperature {
            let action = lockedRecordThermal(temperatureC: temp)
            thermalAction = action
            if action == .tripped {
                await Self.offloadBlocking {
                    do {
                        try deps.processController.terminateProcess(named: actionTarget)
                    } catch {
                        self.logger?.log(.error, operation: "thermal.trip", message: "terminate target failed", metadata: ["target": actionTarget, "error": error.localizedDescription])
                    }
                }
                await store.updateGuardStatus(.overheatTrip)
            }
        }

        return RuntimeCycleResult(connectivityAction: connectivityAction, thermalAction: thermalAction, restartAttempt: restartAttempt)
    }

    public func confirmThermalRecovery() async {
        if lockedConfirmThermalRecovery() == .recovered {
            await store.updateGuardStatus(.active)
        }
    }

    public func updateThermalPolicy(_ policy: ThermalPolicy) {
        lock.lock()
        defer { lock.unlock() }
        thermalController = ThermalProtectionController(policy: policy)
    }

    /// Runs a synchronous, potentially-blocking closure on a GCD global queue
    /// instead of Swift's cooperative thread pool, preventing MainActor starvation.
    ///
    /// System providers (powermetrics, ps, ping) and XPC calls (DispatchSemaphore.wait)
    /// all block their calling thread. Running them on the cooperative pool starves
    /// the limited threads and freezes the UI.
    private static func offloadBlocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }

    private func shouldAttemptAutoRestart(target: String) -> Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        lock.lock()
        let lastAttempt = lastAutoRestartAttemptAt
        lock.unlock()
        guard let lastAttempt else {
            return true
        }
        return Date().timeIntervalSince(lastAttempt) >= autoRestartCooldownSeconds
    }

    private func shouldAttemptFullRestart() -> Bool {
        lock.lock()
        let lastAttempt = lastFullRestartAttemptAt
        lock.unlock()
        guard let lastAttempt else {
            return true
        }
        return Date().timeIntervalSince(lastAttempt) >= fullRestartCooldownSeconds
    }

    /// Extracts the `.app` bundle path from a command string.
    /// e.g. "/Users/x/EXO.app/Contents/Resources/exo/exo" → "/Users/x/EXO.app"
    static func extractAppBundlePath(from command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: ".app", options: .caseInsensitive) else {
            return nil
        }
        let path = String(trimmed[trimmed.startIndex..<range.upperBound])
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }
}
