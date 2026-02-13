import ExoSentryCore
import ExoSentryXPC
import AppKit
import Foundation
import SwiftUI

private enum MenuBarDefaults {
    static let operatingModeRaw = "standard"
    static let targetProcess = "exo"
    static let thermalThreshold = "95"
    static let statusAPIPort: UInt16 = 1988
    static let runtimeLoopIntervalNanoseconds: UInt64 = 5_000_000_000
    static let networkProbeIntervalSeconds: TimeInterval = 60
    static let thermalSampleIntervalSeconds: Int = 5
    static let thermalTripDurationSeconds: Int = 60
    static let thermalRecoverOffsetC: Double = 10
    static let thermalRecoverDurationSeconds: Int = 120
    static let thunderboltInterConfigDelayNanoseconds: UInt64 = 2_000_000_000
    static let thunderboltV6DelayNanoseconds: UInt64 = 3_000_000_000
}

private struct MenuBarSettingsSnapshot {
    let mode: OperatingMode
    let targetProcesses: String
    let thermalThreshold: String
    let apiPort: UInt16
    let wifiAutoRecoveryEnabled: Bool
    let autoRestartEnabled: Bool
    let launchCommand: String
    let thunderboltIPEnabled: Bool
    let thunderboltIPConfigs: [ThunderboltIPConfig]
}

private final class MenuBarSettingsStore {
    private enum Key {
        static let operatingMode = "ExoSentry.operatingMode"
        static let targetProcesses = "ExoSentry.targetProcesses"
        static let thermalThreshold = "ExoSentry.thermalThreshold"
        static let apiPort = "ExoSentry.apiPort"
        static let wifiAutoRecoveryEnabled = "ExoSentry.wifiAutoRecoveryEnabled"
        static let autoRestartEnabled = "ExoSentry.autoRestartEnabled"
        static let launchCommand = "ExoSentry.launchCommand"
        static let thunderboltIPEnabled = "ExoSentry.thunderboltIPEnabled"
        static let thunderboltIPConfigs = "ExoSentry.thunderboltIPConfigs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MenuBarSettingsSnapshot {
        let mode: OperatingMode = {
            let raw = defaults.string(forKey: Key.operatingMode) ?? MenuBarDefaults.operatingModeRaw
            return raw == "cluster" ? .cluster : .standard
        }()
        let targetProcesses = defaults.string(forKey: Key.targetProcesses) ?? MenuBarDefaults.targetProcess
        let thermalThreshold: String = {
            let value = defaults.string(forKey: Key.thermalThreshold)
            return (value?.isEmpty == false) ? value! : MenuBarDefaults.thermalThreshold
        }()
        let apiPort: UInt16 = {
            let value = defaults.integer(forKey: Key.apiPort)
            return value > 0 ? UInt16(value) : MenuBarDefaults.statusAPIPort
        }()
        let wifiAutoRecoveryEnabled = (defaults.object(forKey: Key.wifiAutoRecoveryEnabled) as? Bool) ?? false
        let autoRestartEnabled = defaults.bool(forKey: Key.autoRestartEnabled)
        let launchCommand = defaults.string(forKey: Key.launchCommand) ?? ""
        let thunderboltIPEnabled = defaults.bool(forKey: Key.thunderboltIPEnabled)
        let thunderboltIPConfigs: [ThunderboltIPConfig] = {
            guard let data = defaults.data(forKey: Key.thunderboltIPConfigs) else {
                return ThunderboltIPConfig.defaultConfigs
            }
            return (try? JSONDecoder().decode([ThunderboltIPConfig].self, from: data)) ?? ThunderboltIPConfig.defaultConfigs
        }()

        return MenuBarSettingsSnapshot(
            mode: mode,
            targetProcesses: targetProcesses,
            thermalThreshold: thermalThreshold,
            apiPort: apiPort,
            wifiAutoRecoveryEnabled: wifiAutoRecoveryEnabled,
            autoRestartEnabled: autoRestartEnabled,
            launchCommand: launchCommand,
            thunderboltIPEnabled: thunderboltIPEnabled,
            thunderboltIPConfigs: thunderboltIPConfigs
        )
    }

    func saveMode(_ mode: OperatingMode) {
        defaults.set(mode == .cluster ? "cluster" : "standard", forKey: Key.operatingMode)
    }

    func saveTargetProcesses(_ value: String) {
        defaults.set(value, forKey: Key.targetProcesses)
    }

    func saveThermalThreshold(_ value: String) {
        defaults.set(value, forKey: Key.thermalThreshold)
    }

    func saveAPIPort(_ value: UInt16) {
        defaults.set(Int(value), forKey: Key.apiPort)
    }

    func saveWiFiAutoRecoveryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.wifiAutoRecoveryEnabled)
    }

    func saveAutoRestart(enabled: Bool, launchCommand: String) {
        defaults.set(enabled, forKey: Key.autoRestartEnabled)
        defaults.set(launchCommand, forKey: Key.launchCommand)
    }

    func saveThunderboltIP(enabled: Bool, configs: [ThunderboltIPConfig]) {
        defaults.set(enabled, forKey: Key.thunderboltIPEnabled)
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: Key.thunderboltIPConfigs)
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var payload: StatusPayload
    @Published var selectedMode: OperatingMode
    @Published var targetProcessInput: String
    @Published var thermalTripThresholdInput: String
    @Published var apiPortInput: String
    @Published var currentStatusPort: UInt16
    @Published var wifiAutoRecoveryEnabled: Bool
    @Published var warningMessage: String?
    @Published var batteryHealthMessage: String?
    @Published var autoRestartEnabled: Bool
    @Published var launchCommandInput: String
    @Published var temperatureHistory: [(date: Date, value: Double)] = []
    @Published var thunderboltIPEnabled: Bool
    @Published var thunderboltIPConfigs: [ThunderboltIPConfig]

    static let maxTemperatureSamples = 30

    var showsWarningDot: Bool {
        payload.status == .degraded || payload.status == .overheatTrip
    }

    var loadLevel: ExoSentryTheme.LoadLevel {
        ExoSentryTheme.LoadLevel.from(temperature: payload.tempC)
    }

    var isClamshellEnabled: Bool {
        selectedMode == .cluster
    }

    var apiEndpointURL: String {
        "http://localhost:\(currentStatusPort)"
    }

    let store: AppStateStore
    private let orchestrator: GuardRuntimeOrchestrator
    private let permissionCoordinator: PermissionRepairCoordinator
    private let privilegedClient: PrivilegedCommanding
    private let blessInstaller: HelperBlessInstalling
    private let loginItemManager: LoginItemManaging
    private let statusServer: LocalStatusServer
    let logger: Logging
    private let startupRecovery: StartupRecoveryCoordinator
    private let powerStateProvider: PowerStateProviding
    private let batteryOptimizationProvider: BatteryOptimizationProviding
    private let settingsStore: MenuBarSettingsStore
    private let runtimeLoopCoordinator: MenuBarRuntimeLoopCoordinator

    private var started = false
    private var hasPresentedPermissionRepairPrompt = false
    private var lastNetworkProbeAt: Date?

    init() {
        let settingsStore = MenuBarSettingsStore()
        let settings = settingsStore.load()
        let savedMode = settings.mode
        let savedTargets = settings.targetProcesses
        let savedThreshold = settings.thermalThreshold
        let savedPort = settings.apiPort
        let savedWiFiAutoRecoveryEnabled = settings.wifiAutoRecoveryEnabled
        let savedAutoRestart = settings.autoRestartEnabled
        let savedLaunchCommand = settings.launchCommand
        let savedThunderboltIPEnabled = settings.thunderboltIPEnabled
        let savedThunderboltIPConfigs = settings.thunderboltIPConfigs

        let targetList = savedTargets.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let effectiveTargets = targetList.isEmpty ? [MenuBarDefaults.targetProcess] : targetList

        let privilegedClient = PrivilegedXPCClient()
        let sleepController = PrivilegedSleepSettingsController(privilegedClient: privilegedClient)
        let guardCoordinator = GuardCoordinator(sleepController: sleepController)
        let store = AppStateStore(initialMode: savedMode, targetProcess: effectiveTargets.joined(separator: ", "))

        let dependencies = RuntimeDependencies(
            processProvider: SystemProcessSnapshotProvider(),
            networkProbe: SystemNetworkProbeService(),
            temperatureProvider: PrivilegedTemperatureProvider(client: privilegedClient),
            powerManager: PowerAssertionManager(),
            sleepCoordinator: guardCoordinator
        )

        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ExoSentry.log")
        let logger = SecureLogger(fileURL: logPath)

        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            dependencies: dependencies,
            mode: savedMode,
            targets: effectiveTargets,
            autoRestartEnabled: savedAutoRestart,
            launchCommand: savedLaunchCommand,
            logger: logger
        )

        // Apply persisted thermal threshold
        if let threshold = Double(savedThreshold), threshold > 0 {
            orchestrator.updateThermalPolicy(
                ThermalPolicy(
                    sampleIntervalSeconds: MenuBarDefaults.thermalSampleIntervalSeconds,
                    tripTemperatureC: threshold,
                    tripDurationSeconds: MenuBarDefaults.thermalTripDurationSeconds,
                    recoverTemperatureC: max(0, threshold - MenuBarDefaults.thermalRecoverOffsetC),
                    recoverDurationSeconds: MenuBarDefaults.thermalRecoverDurationSeconds
                )
            )
        }

        self.store = store
        self.orchestrator = orchestrator
        self.privilegedClient = privilegedClient
        self.permissionCoordinator = PermissionRepairCoordinator(privilegedClient: privilegedClient, stateStore: store)
        self.blessInstaller = HelperBlessInstaller()
        self.loginItemManager = LoginItemManager()
        self.powerStateProvider = SystemPowerStateProvider()
        self.batteryOptimizationProvider = SystemBatteryOptimizationProvider()
        self.settingsStore = settingsStore
        self.runtimeLoopCoordinator = MenuBarRuntimeLoopCoordinator(intervalNanoseconds: MenuBarDefaults.runtimeLoopIntervalNanoseconds)

        self.logger = logger
        self.startupRecovery = StartupRecoveryCoordinator(guardCoordinator: guardCoordinator, logger: logger)

        self.statusServer = LocalStatusServer(payloadProvider: {
            await store.snapshotStatus(lastUpdated: ISO8601Timestamp.string(from: Date()))
        })

        self.selectedMode = savedMode
        self.targetProcessInput = effectiveTargets.joined(separator: ", ")
        self.thermalTripThresholdInput = savedThreshold
        self.apiPortInput = String(savedPort)
        self.currentStatusPort = savedPort
        self.wifiAutoRecoveryEnabled = savedWiFiAutoRecoveryEnabled
        self.autoRestartEnabled = savedAutoRestart
        self.launchCommandInput = savedLaunchCommand
        self.thunderboltIPEnabled = savedThunderboltIPEnabled
        self.thunderboltIPConfigs = savedThunderboltIPConfigs
        self.warningMessage = nil
        self.batteryHealthMessage = nil
        self.payload = StatusPayload(
            status: .paused,
            mode: savedMode,
            tempC: nil,
            isCharging: false,
            lidClosed: false,
            targetProcess: effectiveTargets.joined(separator: ", "),
            targetProcessRunning: false,
            networkState: .ok,
            lastUpdated: ISO8601Timestamp.string(from: Date())
        )
    }

    // MARK: - Persistence

    private func persistMode() {
        settingsStore.saveMode(selectedMode)
    }

    private func persistTargetProcesses() {
        settingsStore.saveTargetProcesses(targetProcessInput)
    }

    private func persistThermalThreshold() {
        settingsStore.saveThermalThreshold(thermalTripThresholdInput)
    }

    private func persistAPIPort() {
        settingsStore.saveAPIPort(currentStatusPort)
    }

    private func persistWiFiAutoRecoverySetting() {
        settingsStore.saveWiFiAutoRecoveryEnabled(wifiAutoRecoveryEnabled)
    }

    private func persistAutoRestart() {
        settingsStore.saveAutoRestart(enabled: autoRestartEnabled, launchCommand: launchCommandInput)
    }

    func persistThunderboltIPConfigs() {
        settingsStore.saveThunderboltIP(enabled: thunderboltIPEnabled, configs: thunderboltIPConfigs)
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else {
            return
        }
        started = true
        startupRecovery.recoverOnLaunch()

        if thunderboltIPEnabled {
            applyThunderboltIPConfigs()
        }

        let initialPort = UInt16(apiPortInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? MenuBarDefaults.statusAPIPort
        currentStatusPort = initialPort
        apiPortInput = String(initialPort)

        do {
            try statusServer.start(port: currentStatusPort)
        } catch {
            logger.log(.error, operation: "statusServer.start", message: "start failed", metadata: ["error": error.localizedDescription])
        }

        runtimeLoopCoordinator.start { [weak self] in
            guard let self else {
                return
            }
            let shouldProbeNetwork = shouldProbeNetworkNow()
            let cycleResult = await orchestrator.runCycle(probeNetwork: shouldProbeNetwork)
            if shouldProbeNetwork {
                lastNetworkProbeAt = Date()
            }
            await applyRuntimeActions(cycleResult)
            let isCharging = await refreshPowerState()
            updateBatteryHealthMessage(isCharging: isCharging)
            await permissionCoordinator.refreshWarningState()
            await promptPermissionRepairIfNeeded()
            await refreshSnapshot()
        }

        Task {
            await refreshSnapshot()
        }
    }

    func stop() {
        runtimeLoopCoordinator.stop()
        statusServer.stop()
        started = false
    }

    // MARK: - Settings Application

    func applyMode() {
        persistMode()
        Task {
            await orchestrator.updateMode(selectedMode)
            await refreshSnapshot()
        }
    }

    func applyTargetProcess() {
        let targets = parseTargetProcesses(from: targetProcessInput)
        guard !targets.isEmpty else {
            warningMessage = "目标进程列表不能为空"
            return
        }
        targetProcessInput = targets.joined(separator: ", ")
        orchestrator.updateTargets(targets)
        persistTargetProcesses()
        Task {
            await store.updateTargetProcess(targets.joined(separator: ", "), running: false)
            await refreshSnapshot()
        }
    }

    func applyThermalThreshold() {
        let trimmed = thermalTripThresholdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let threshold = Double(trimmed), threshold > 0 else {
            warningMessage = "温度阈值必须是正数"
            return
        }

        orchestrator.updateThermalPolicy(
            ThermalPolicy(
                sampleIntervalSeconds: MenuBarDefaults.thermalSampleIntervalSeconds,
                tripTemperatureC: threshold,
                tripDurationSeconds: MenuBarDefaults.thermalTripDurationSeconds,
                recoverTemperatureC: max(0, threshold - MenuBarDefaults.thermalRecoverOffsetC),
                recoverDurationSeconds: MenuBarDefaults.thermalRecoverDurationSeconds
            )
        )
        thermalTripThresholdInput = String(format: "%.0f", threshold)
        persistThermalThreshold()
        warningMessage = "已应用温度阈值"
    }

    func applyStatusAPIPort() {
        let trimmed = apiPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(trimmed), port > 0 else {
            warningMessage = "API 端口必须在 1-65535"
            return
        }

        apiPortInput = String(port)

        guard started else {
            currentStatusPort = port
            persistAPIPort()
            warningMessage = "已应用 API 端口"
            return
        }

        if port == currentStatusPort {
            warningMessage = "API 端口未变化"
            return
        }

        statusServer.stop()
        do {
            try statusServer.start(port: port)
            currentStatusPort = port
            persistAPIPort()
            warningMessage = "已应用 API 端口"
        } catch {
            do {
                try statusServer.start(port: currentStatusPort)
            } catch {
                logger.log(.error, operation: "statusServer.recover", message: "recover failed", metadata: ["error": error.localizedDescription])
            }
            warningMessage = "API 端口应用失败: \(error.localizedDescription)"
            logger.log(.error, operation: "statusServer.rebind", message: "rebind failed", metadata: ["error": error.localizedDescription])
        }
    }

    func applyTargetProcessList(_ processes: [String]) {
        guard !processes.isEmpty else {
            warningMessage = "目标进程列表不能为空"
            return
        }
        targetProcessInput = processes.joined(separator: ", ")
        orchestrator.updateTargets(processes)
        persistTargetProcesses()
        Task {
            await store.updateTargetProcess(processes.joined(separator: ", "), running: false)
            await refreshSnapshot()
        }
        warningMessage = "已应用进程列表"
    }

    func applyWiFiAutoRecoverySetting() {
        persistWiFiAutoRecoverySetting()
        warningMessage = wifiAutoRecoveryEnabled ? "已启用 Wi-Fi 自恢复" : "已禁用 Wi-Fi 自恢复"
    }

    func applyAutoRestartSettings() {
        orchestrator.updateAutoRestart(enabled: autoRestartEnabled, command: launchCommandInput)
        persistAutoRestart()
        warningMessage = autoRestartEnabled ? "已启用自动重启" : "已关闭自动重启"
    }

    func applyThunderboltIPConfigs() {
        persistThunderboltIPConfigs()
        let enabledConfigs = thunderboltIPConfigs.filter { $0.enabled }
        guard !enabledConfigs.isEmpty else {
            warningMessage = "没有启用的雷电端口配置"
            return
        }
        warningMessage = "正在应用雷电端口 IP 配置..."
        Task {
            var successCount = 0
            var failCount = 0
            var firstFailureMessage: String?
            for (index, config) in enabledConfigs.enumerated() {
                // 每次 networksetup 调用之间等待 2 秒，让 configd 稳定，避免干扰 Wi-Fi
                if index > 0 {
                    try? await Task.sleep(nanoseconds: MenuBarDefaults.thunderboltInterConfigDelayNanoseconds)
                }
                do {
                    try await runBlockingUtility {
                        try self.privilegedClient.setStaticIP(service: config.service, ip: config.ip, subnet: config.subnet, router: config.router)
                    }
                    // setStaticIP 和 setV6LinkLocal 之间也等待 1 秒
                    try? await Task.sleep(nanoseconds: MenuBarDefaults.thunderboltV6DelayNanoseconds)
                    try await runBlockingUtility {
                        try self.privilegedClient.setV6LinkLocal(service: config.service)
                    }
                    logger.log(.info, operation: "thunderbolt.setStaticIP", message: "set \(config.service) → \(config.ip)", metadata: [:])
                    successCount += 1
                } catch {
                    logger.log(.error, operation: "thunderbolt.setStaticIP", message: "failed \(config.service)", metadata: ["error": error.localizedDescription])
                    if firstFailureMessage == nil {
                        firstFailureMessage = "\(config.service): \(error.localizedDescription)"
                    }
                    failCount += 1
                }
            }
            if failCount == 0 {
                warningMessage = "已应用 \(successCount) 个雷电端口 IP 配置"
            } else {
                if let firstFailureMessage {
                    warningMessage = "雷电 IP 配置: \(successCount) 成功, \(failCount) 失败（\(firstFailureMessage)）"
                } else {
                    warningMessage = "雷电 IP 配置: \(successCount) 成功, \(failCount) 失败"
                }
            }
        }
    }

    func testLaunchCommand() {
        let cmd = launchCommandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            warningMessage = "启动命令为空，无法测试"
            return
        }
        warningMessage = "正在执行测试命令..."
        Task {
            do {
                try await runBlockingUtility {
                    let controller = SystemProcessController()
                    try controller.launchCommand(cmd)
                }
                warningMessage = "已执行启动命令"
            } catch {
                warningMessage = "执行失败: \(error.localizedDescription)"
            }
        }
    }

    func setAutoRestart(_ enabled: Bool) {
        autoRestartEnabled = enabled
        applyAutoRestartSettings()
    }

    // MARK: - Actions

    func repairPrivileges() {
        Task {
            do {
                try blessInstaller.installPrivilegedHelper()
                try await permissionCoordinator.repairIfNeeded()
                warningMessage = nil
            } catch {
                warningMessage = "权限修复失败: \(error.localizedDescription)"
                logger.log(.error, operation: "permission.repair", message: "repair failed", metadata: ["error": error.localizedDescription])
            }
            await refreshSnapshot()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemManager.setLaunchAtLogin(enabled: enabled)
        } catch {
            warningMessage = "开机自启设置失败: \(error.localizedDescription)"
        }
    }

    func confirmThermalRecovery() {
        Task {
            await orchestrator.confirmThermalRecovery()
            await refreshSnapshot()
        }
    }

    func setClamshellMode(_ enabled: Bool) {
        selectedMode = enabled ? .cluster : .standard
        applyMode()
    }

    func copyAPIEndpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(apiEndpointURL, forType: .string)
        warningMessage = "已复制 API 地址"
    }

    func openLogFile() {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ExoSentry.log")
        NSWorkspace.shared.selectFile(logPath.path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Private

    private func promptPermissionRepairIfNeeded() async {
        let warning = await store.permissionWarningState()
        if warning == .warning {
            guard !hasPresentedPermissionRepairPrompt else {
                return
            }
            hasPresentedPermissionRepairPrompt = true
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要权限修复"
            alert.informativeText = "检测到权限丢失，修复时将提示输入管理员密码。"
            alert.addButton(withTitle: "立即修复")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                repairPrivileges()
            }
            return
        }
        hasPresentedPermissionRepairPrompt = false
    }

    private func applyRuntimeActions(_ result: RuntimeCycleResult) async {
        if case .some(.retry(_, _)) = result.connectivityAction {
            guard wifiAutoRecoveryEnabled else {
                logger.log(.info, operation: "network.restartWiFi", message: "skipped by policy (disabled)", metadata: [:])
                return
            }
            do {
                try await runBlockingUtility {
                    try self.privilegedClient.restartWiFi()
                }
            } catch {
                warningMessage = "网络恢复失败: \(error.localizedDescription)"
                logger.log(.error, operation: "network.restartWiFi", message: "restart failed", metadata: ["error": error.localizedDescription])
            }
        }

        if let attempt = result.restartAttempt {
            switch attempt.kind {
            case .normal:
                if let err = attempt.error {
                    warningMessage = "重启尝试 #\(attempt.failureCount) 失败: \(err)"
                } else {
                    warningMessage = "重启尝试 #\(attempt.failureCount)，等待进程启动..."
                }
            case .fullRestart:
                if let err = attempt.error {
                    warningMessage = "完整重启失败: \(err)"
                } else {
                    warningMessage = "已执行完整重启（杀进程→重开应用→启动服务）"
                }
            }
        }
    }

    private func refreshPowerState() async -> Bool {
        let charging = powerStateProvider.isCharging()
        await store.updateCharging(charging)
        await store.updateLidClosed(powerStateProvider.isLidClosed())
        return charging
    }

    private func updateBatteryHealthMessage(isCharging: Bool) {
        guard isCharging else {
            batteryHealthMessage = nil
            return
        }
        switch batteryOptimizationProvider.optimizedChargingState() {
        case .enabled:
            batteryHealthMessage = nil
        case .disabled:
            batteryHealthMessage = "检测到未开启优化电池充电，建议启用并可配合 AlDente 限制充电阈值。"
        case .unknown:
            batteryHealthMessage = nil
        }
    }

    private func refreshSnapshot() async {
        let newPayload = await store.snapshotStatus(lastUpdated: ISO8601Timestamp.string(from: Date()))
        if shouldPublishMenuUpdate(newPayload) {
            payload = newPayload
        }
        appendTemperatureSample(newPayload.tempC)
    }

    private func shouldPublishMenuUpdate(_ newPayload: StatusPayload) -> Bool {
        return payload.status != newPayload.status ||
            payload.mode != newPayload.mode ||
            payload.tempC != newPayload.tempC ||
            payload.isCharging != newPayload.isCharging ||
            payload.lidClosed != newPayload.lidClosed ||
            payload.targetProcess != newPayload.targetProcess ||
            payload.targetProcessRunning != newPayload.targetProcessRunning ||
            payload.networkState != newPayload.networkState
    }

    private func appendTemperatureSample(_ tempC: Double?) {
        guard let temp = tempC else { return }
        temperatureHistory.append((date: Date(), value: temp))
        if temperatureHistory.count > Self.maxTemperatureSamples {
            temperatureHistory.removeFirst(temperatureHistory.count - Self.maxTemperatureSamples)
        }
    }

    func parseTargetProcesses(from raw: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in raw.split(separator: ",") {
            let trimmed = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }

        return ordered
    }

    private func shouldProbeNetworkNow() -> Bool {
        guard let lastNetworkProbeAt else {
            return true
        }
        return Date().timeIntervalSince(lastNetworkProbeAt) >= MenuBarDefaults.networkProbeIntervalSeconds
    }

    private func runBlockingUtility<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility) {
            try work()
        }.value
    }
}
