import ExoSentryCore
import ExoSentryXPC
import AppKit
import Foundation
import SwiftUI

extension GuardStatus {
    var displayName: String {
        switch self {
        case .active: return "守护中"
        case .paused: return "已暂停"
        case .degraded: return "已降级"
        case .overheatTrip: return "过热熔断"
        }
    }
}

extension OperatingMode {
    var displayName: String {
        switch self {
        case .cluster: return "集群"
        case .standard: return "标准"
        }
    }
}

extension NetworkState {
    var displayName: String {
        switch self {
        case .ok: return "正常"
        case .lanLost: return "局域网断开"
        case .wanLost: return "外网断开"
        case .offline: return "离线"
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var payload: StatusPayload
    @Published var selectedMode: OperatingMode
    @Published var targetProcessInput: String
    @Published var warningMessage: String?
    @Published var batteryHealthMessage: String?

    var showsWarningDot: Bool {
        payload.status == .degraded || payload.status == .overheatTrip
    }

    private let store: AppStateStore
    private let orchestrator: GuardRuntimeOrchestrator
    private let permissionCoordinator: PermissionRepairCoordinator
    private let privilegedClient: PrivilegedCommanding
    private let blessInstaller: HelperBlessInstalling
    private let loginItemManager: LoginItemManaging
    private let statusServer: LocalStatusServer
    private let logger: Logging
    private let startupRecovery: StartupRecoveryCoordinator
    private let powerStateProvider: PowerStateProviding
    private let batteryOptimizationProvider: BatteryOptimizationProviding
    private let formatter = ISO8601DateFormatter()

    private var cycleTask: Task<Void, Never>?
    private var started = false
    private var hasPresentedPermissionRepairPrompt = false

    init() {
        let privilegedClient = PrivilegedXPCClient()
        let sleepController = PrivilegedSleepSettingsController(privilegedClient: privilegedClient)
        let guardCoordinator = GuardCoordinator(sleepController: sleepController)
        let store = AppStateStore(initialMode: .standard, targetProcess: "exo")

        let dependencies = RuntimeDependencies(
            processProvider: SystemProcessSnapshotProvider(),
            networkProbe: SystemNetworkProbeService(),
            temperatureProvider: PowermetricsTemperatureProvider(),
            powerManager: PowerAssertionManager(),
            sleepCoordinator: guardCoordinator
        )

        let orchestrator = GuardRuntimeOrchestrator(
            store: store,
            dependencies: dependencies,
            mode: .standard,
            targets: ["exo"]
        )

        self.store = store
        self.orchestrator = orchestrator
        self.privilegedClient = privilegedClient
        self.permissionCoordinator = PermissionRepairCoordinator(privilegedClient: privilegedClient, stateStore: store)
        self.blessInstaller = HelperBlessInstaller()
        self.loginItemManager = LoginItemManager()
        self.powerStateProvider = SystemPowerStateProvider()
        self.batteryOptimizationProvider = SystemBatteryOptimizationProvider()

        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ExoSentry.log")
        let logger = SecureLogger(fileURL: logPath)
        self.logger = logger
        self.startupRecovery = StartupRecoveryCoordinator(guardCoordinator: guardCoordinator, logger: logger)

        self.statusServer = LocalStatusServer(payloadProvider: {
            await store.snapshotStatus(lastUpdated: ISO8601DateFormatter().string(from: Date()))
        })

        self.selectedMode = .standard
        self.targetProcessInput = "exo"
        self.warningMessage = nil
        self.batteryHealthMessage = nil
        self.payload = StatusPayload(
            status: .paused,
            mode: .standard,
            tempC: nil,
            isCharging: false,
            lidClosed: false,
            targetProcess: "exo",
            targetProcessRunning: false,
            networkState: .ok,
            lastUpdated: formatter.string(from: Date())
        )
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        startupRecovery.recoverOnLaunch()
        do {
            try statusServer.start(port: 1988)
        } catch {
            logger.log(.error, operation: "statusServer.start", message: "start failed", metadata: ["error": error.localizedDescription])
        }

        cycleTask = Task {
            while !Task.isCancelled {
                let cycleResult = await orchestrator.runCycle()
                await applyRuntimeActions(cycleResult)
                let isCharging = await refreshPowerState()
                updateBatteryHealthMessage(isCharging: isCharging)
                await permissionCoordinator.refreshWarningState()
                await promptPermissionRepairIfNeeded()
                await refreshSnapshot()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        Task {
            await refreshSnapshot()
        }
    }

    func stop() {
        cycleTask?.cancel()
        statusServer.stop()
        started = false
    }

    func applyMode() {
        Task {
            await orchestrator.updateMode(selectedMode)
            await refreshSnapshot()
        }
    }

    func applyTargetProcess() {
        let trimmed = targetProcessInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            warningMessage = "目标进程不能为空"
            return
        }
        orchestrator.updateTargets([trimmed])
        Task {
            await store.updateTargetProcess(trimmed, running: false)
            await refreshSnapshot()
        }
    }

    func applyFromMenu() {
        applyMode()
        applyTargetProcess()
        if !targetProcessInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warningMessage = "已应用设置"
        }
    }

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

    func confirmThermalRecovery() {
        Task {
            await orchestrator.confirmThermalRecovery()
            await refreshSnapshot()
        }
    }

    func showAbout() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ExoSentry"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "关于 \(appName)"
        alert.informativeText = "版本 \(version) (\(build))\n\nExoSentry 是用于守护目标进程并管理休眠、网络与过热保护的菜单栏工具。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    func showUsageGuide() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "软件使用说明"
        alert.informativeText = "1. 在“模式”中选择标准或集群。\n2. 标准模式：防系统休眠，不启用闭盖与网络守护。\n3. 集群模式：防系统休眠+防显示器休眠，允许闭盖并启用网络守护。\n4. 在“目标进程”输入并应用进程名（默认 exo），进程停止会尝试自动拉起。\n5. 出现权限异常时点击“一键修复”；过热熔断后点击“手动恢复”。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    private func applyRuntimeActions(_ result: RuntimeCycleResult) async {
        if case .some(.retry(_, _)) = result.connectivityAction {
            do {
                try privilegedClient.restartWiFi()
            } catch {
                warningMessage = "网络恢复失败: \(error.localizedDescription)"
                logger.log(.error, operation: "network.restartWiFi", message: "restart failed", metadata: ["error": error.localizedDescription])
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
        let newPayload = await store.snapshotStatus(lastUpdated: formatter.string(from: Date()))
        if shouldPublishMenuUpdate(newPayload) {
            payload = newPayload
        }
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
}

struct MenuBarRootView: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.showsWarningDot {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                    Text("告警")
                        .font(.caption)
                }
            }

            Text("状态: \(model.payload.status.displayName)")
            Text("模式: \(model.payload.mode.displayName)")
            Text("目标进程: \(model.payload.targetProcess) \(model.payload.targetProcessRunning ? "(运行中)" : "(已停止)")")
            Text("网络: \(model.payload.networkState.displayName)")

            Text("高负载闭盖有屏幕受热风险，建议使用微开支架或散热底座。")
                .font(.caption)
                .foregroundStyle(.orange)

            Picker("模式", selection: $model.selectedMode) {
                Text("集群").tag(OperatingMode.cluster)
                Text("标准").tag(OperatingMode.standard)
            }
            .onChange(of: model.selectedMode) { _ in
                model.applyMode()
            }

            HStack {
                TextField("目标进程", text: $model.targetProcessInput)
                Button("应用设置") {
                    model.applyFromMenu()
                }
            }

            Toggle("开机自启", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    model.setLaunchAtLogin(newValue)
                }

            if model.payload.status == .degraded {
                HStack {
                    Text("权限异常")
                    Button("一键修复") {
                        model.repairPrivileges()
                    }
                }
            }

            if model.payload.status == .overheatTrip {
                HStack {
                    Text("高温已熔断")
                    Button("手动恢复") {
                        model.confirmThermalRecovery()
                    }
                }
            }

            if let warning = model.warningMessage {
                Text(warning)
                    .foregroundStyle(warning == "已应用设置" ? .green : .red)
                    .font(.caption)
            }

            if let batteryWarning = model.batteryHealthMessage {
                Text(batteryWarning)
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Divider()
            Button("关于") {
                model.showAbout()
            }
            Button("软件使用说明") {
                model.showUsageGuide()
            }
            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            model.start()
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("General") {
                Picker("模式", selection: $model.selectedMode) {
                    Text("集群").tag(OperatingMode.cluster)
                    Text("标准").tag(OperatingMode.standard)
                }
                Toggle("开机自启", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        model.setLaunchAtLogin(newValue)
                    }
            }

            Section("Triggers") {
                TextField("目标进程", text: $model.targetProcessInput)
                Button("应用目标进程") {
                    model.applyTargetProcess()
                }
            }

            Section("Protection") {
                Button("应用模式") {
                    model.applyMode()
                }
                if model.payload.status == .degraded {
                    Button("一键修复权限") {
                        model.repairPrivileges()
                    }
                }
                if model.payload.status == .overheatTrip {
                    Button("手动恢复") {
                        model.confirmThermalRecovery()
                    }
                }
            }

            Section("Network") {
                Text("当前网络: \(model.payload.networkState.displayName)")
            }

            Section("安全提示") {
                Text("高负载闭盖可能导致屏幕受热风险，建议使用微开支架或散热底座。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let batteryWarning = model.batteryHealthMessage {
                    Text(batteryWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(width: 460, height: 320)
    }
}

@main
struct ExoSentryMenuBarApp: App {
    @StateObject private var model = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName(for: model.payload.status))
                if model.showsWarningDot {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                }
            }
        }

        Settings {
            PreferencesView(model: model)
        }
        .defaultSize(width: 420, height: 180)
    }

    private func iconName(for status: GuardStatus) -> String {
        switch status {
        case .active:
            return "circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .overheatTrip:
            return "flame.fill"
        }
    }
}
