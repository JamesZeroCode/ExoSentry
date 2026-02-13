import Charts
import ExoSentryCore
import SwiftUI

// MARK: - Sidebar Navigation

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "常规"
    case protection = "保护"
    case triggers = "触发器"
    case network = "网络"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .protection: return "shield"
        case .triggers: return "bolt.fill"
        case .network: return "network"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var selectedTab: PreferencesTab = .general
    @State private var hoveredTab: PreferencesTab?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PreferencesTab.allCases) { tab in
                    sidebarButton(tab: tab)
                }

                Spacer()

                // Bottom status
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.payload.status == .active ? ExoSentryTheme.primary : .secondary)
                            .frame(width: 7, height: 7)
                        Text("EXOSENTRY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("状态: \(model.payload.status.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .padding(.top, 12)
            .frame(width: 160)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 0) {
                selectedContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 480)
    }

    private func sidebarButton(tab: PreferencesTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab && !isSelected
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? ExoSentryTheme.primary : .secondary)
                Text(tab.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? ExoSentryTheme.primary.opacity(0.12)
                    : (isHovered ? Color.primary.opacity(0.06) : .clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredTab = hovering ? tab : nil
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .general:
            GeneralPanel(model: model)
        case .protection:
            ProtectionPanel(model: model)
        case .triggers:
            TriggersPanel(model: model)
        case .network:
            NetworkPanel(model: model)
        case .about:
            AboutPanel(model: model)
        }
    }
}

// MARK: - General Panel

private struct GeneralPanel: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var launchAtLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("常规设置")
                    .font(.title2)
                    .fontWeight(.bold)

                // Launch at login
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("应用启动", systemImage: "power")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                                .foregroundStyle(ExoSentryTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("开机自启")
                                    .font(.body)
                                Text("登录 macOS 时自动启动 ExoSentry")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .onChange(of: launchAtLogin) { newValue in
                                    model.setLaunchAtLogin(newValue)
                                }
                        }
                    }
                }

                // Clamshell mode
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("硬件性能", systemImage: "cpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Image(systemName: "laptopcomputer.and.arrow.down")
                                .font(.title3)
                                .foregroundStyle(ExoSentryTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("开启合盖模式")
                                    .font(.body)
                                Text("允许笔记本合盖时节点继续运行")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.isClamshellEnabled },
                                set: { model.setClamshellMode($0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption2)
                            Text("注意：合盖模式会增加 M1/M2/M3 芯片的热负荷，建议使用微开支架或散热底座")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                // Sleep prevention
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("睡眠防止", systemImage: "moon.zzz")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let behavior = ModeBehavior.forMode(model.selectedMode)

                        sleepRow(
                            title: "防止显示器休眠",
                            isEnabled: behavior.preventDisplaySleep
                        )
                        sleepRow(
                            title: "防止系统休眠",
                            isEnabled: behavior.preventSystemSleep
                        )

                        Text("睡眠策略由当前模式决定（当前: \(model.selectedMode.displayName)模式）")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func sleepRow(title: String, isEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isEnabled ? ExoSentryTheme.primary : .secondary)
                .font(.body)
            Text(title)
                .font(.body)
            Spacer()
        }
    }
}

// MARK: - Protection Panel

private struct ProtectionPanel: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var thresholdValue: Double = 95

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("保护与性能")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("配置 M 系列集群节点的自动保护机制")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    // Temperature card
                    settingsCard {
                        VStack(spacing: 8) {
                            HStack {
                                Text("当前 SoC 温度")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "thermometer.medium")
                                    .foregroundStyle(ExoSentryTheme.primary)
                            }

                            if let temp = model.payload.tempC {
                                Text("\(Int(temp))°C")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(model.loadLevel.color)
                            } else {
                                Text("--°C")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            temperatureChart
                        }
                    }

                    // Threshold card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("温度阈值")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(thresholdValue))°C")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(ExoSentryTheme.primary)
                            }

                            Slider(value: $thresholdValue, in: 40...105, step: 1)
                                .tint(ExoSentryTheme.primary)
                                .onChange(of: thresholdValue) { newValue in
                                    model.thermalTripThresholdInput = String(format: "%.0f", newValue)
                                }

                            HStack {
                                Text("40°C")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("105°C")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Button("应用阈值") {
                                model.applyThermalThreshold()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .tint(ExoSentryTheme.primary)

                            if let warning = model.warningMessage, warning.contains("温度") {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(ExoSentryTheme.primary)
                            }
                        }
                    }
                }

                // Overheat recovery
                if model.payload.status == .overheatTrip {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.red)
                        Text("过热熔断已触发")
                            .font(.headline)
                        Spacer()
                        Button("手动恢复") {
                            model.confirmThermalRecovery()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Degraded recovery
                if model.payload.status == .degraded {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("权限异常")
                            .font(.headline)
                        Spacer()
                        Button("一键修复") {
                            model.repairPrivileges()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }
            .padding(20)
        }
        .onAppear {
            if let val = Double(model.thermalTripThresholdInput) {
                thresholdValue = val
            }
        }
    }

    @ViewBuilder
    private var temperatureChart: some View {
        if !model.temperatureHistory.isEmpty {
            Chart {
                ForEach(Array(model.temperatureHistory.enumerated()), id: \.offset) { index, sample in
                    LineMark(
                        x: .value("时间", index),
                        y: .value("温度", sample.value)
                    )
                    .foregroundStyle(ExoSentryTheme.primary)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("时间", index),
                        y: .value("温度", sample.value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [ExoSentryTheme.primary.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 30...110)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 20)) {
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 80)
        } else {
            Text("等待温度数据（如持续为空，请先点一键修复）")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(height: 80)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Triggers Panel

private struct TriggersPanel: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var processList: [String] = []
    @State private var newProcessName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("触发器")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("当以下任一进程运行时，自动激活守护保护")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("进程名区分大小写（如 exo ≠ EXO），请用 ps -axo comm= 确认实际名称")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Process list header
            HStack {
                Text("进程守护列表")
                    .font(.headline)
                Spacer()
                Text("受保护的进程将阻止系统进入睡眠")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            List {
                ForEach(processList, id: \.self) { process in
                    HStack(spacing: 10) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(ExoSentryTheme.primary)
                            .font(.system(size: 14))
                            .frame(width: 24, height: 24)
                            .background(ExoSentryTheme.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(process)
                                .font(.system(.body, design: .monospaced))
                        }
                        Spacer()
                        if isProcessRunning(process) {
                            Text("运行中")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ExoSentryTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ExoSentryTheme.primary.opacity(0.1))
                                .clipShape(Capsule())
                        } else {
                            Text("未运行")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        HoverableIconButton(
                            icon: "minus.circle.fill",
                            color: .red.opacity(0.7),
                            hoverColor: .red
                        ) {
                            removeProcess(process)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            // Add process
            HStack(spacing: 8) {
                TextField("输入进程名称", text: $newProcessName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addProcess()
                    }
                Button {
                    addProcess()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(newProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary : ExoSentryTheme.primary)
                }
                .buttonStyle(.plain)
                .disabled(newProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .hoverScale(1.15)
            }
            .padding(.horizontal, 20)

            // Apply button
            HStack {
                if let warning = model.warningMessage, warning.contains("进程") {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(ExoSentryTheme.primary)
                }
                Spacer()
                Button("应用更改") {
                    model.applyTargetProcessList(processList)
                }
                .buttonStyle(.borderedProminent)
                .tint(ExoSentryTheme.primary)
                .disabled(processList.isEmpty)
            }
            .padding(.horizontal, 20)

            // Auto-restart section
            autoRestartSection
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .onAppear {
            processList = model.parseTargetProcesses(from: model.targetProcessInput)
        }
    }

    private var autoRestartSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("自动重启", systemImage: "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(model.autoRestartEnabled ? ExoSentryTheme.primary : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("进程停止时自动重启")
                            .font(.body)
                        Text("当目标进程退出后自动执行启动命令（每 15 秒检测一次）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.autoRestartEnabled },
                        set: { model.setAutoRestart($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if model.autoRestartEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("启动命令")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("例如: /opt/homebrew/bin/exo", text: $model.launchCommandInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button("应用") {
                                model.applyAutoRestartSettings()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .tint(ExoSentryTheme.primary)
                            Button("测试执行") {
                                model.testLaunchCommand()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                        Text("留空则使用 env + 进程名启动；支持 shell 命令，如 \"cd /path && ./start.sh\"")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("连续 3 次重启失败后，将自动强制退出并重新打开 .app 再启动服务")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let warning = model.warningMessage, warning.contains("重启") {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(ExoSentryTheme.primary)
                }
            }
        }
    }

    private func addProcess() {
        let trimmed = newProcessName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !processList.contains(trimmed) else { return }
        processList.append(trimmed)
        newProcessName = ""
    }

    private func removeProcess(_ process: String) {
        processList.removeAll { $0 == process }
    }

    private func isProcessRunning(_ process: String) -> Bool {
        let currentTargets = model.parseTargetProcesses(from: model.payload.targetProcess)
        return currentTargets.contains(process) && model.payload.targetProcessRunning
    }
}

// MARK: - Network Panel

private struct NetworkPanel: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("网络")
                    .font(.title2)
                    .fontWeight(.bold)

                // Network status
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("网络状态", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Image(systemName: networkIcon)
                                .font(.title2)
                                .foregroundStyle(networkColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前状态")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(model.payload.networkState.displayName)
                                    .font(.headline)
                            }
                        }
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("网络自恢复", systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(
                            "检测到网络异常时自动重启 Wi-Fi",
                            isOn: Binding(
                                get: { model.wifiAutoRecoveryEnabled },
                                set: { newValue in
                                    model.wifiAutoRecoveryEnabled = newValue
                                    model.applyWiFiAutoRecoverySetting()
                                }
                            )
                        )
                        .toggleStyle(.switch)

                        Text("默认关闭。关闭时仅做网络状态检测，不会执行 Wi-Fi 开关动作。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if let warning = model.warningMessage, warning.contains("Wi-Fi") {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(ExoSentryTheme.primary)
                        }
                    }
                }

                // API configuration
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("状态 API 配置", systemImage: "server.rack")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text("端口")
                                .font(.body)
                            TextField("端口", text: $model.apiPortInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Button("应用") {
                                model.applyStatusAPIPort()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .tint(ExoSentryTheme.primary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API 端点")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(model.apiEndpointURL)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    model.copyAPIEndpoint()
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                            }
                        }

                        if let warning = model.warningMessage, warning.contains("API") || warning.contains("端口") {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(warning.contains("失败") ? .red : ExoSentryTheme.primary)
                        }
                    }
                }

                // Thunderbolt IP configuration
                ThunderboltIPCard(model: model)

                Spacer()
            }
            .padding(20)
        }
    }

    private var networkIcon: String {
        switch model.payload.networkState {
        case .ok: return "wifi"
        case .lanLost: return "wifi.exclamationmark"
        case .wanLost: return "wifi.exclamationmark"
        case .offline: return "wifi.slash"
        }
    }

    private var networkColor: Color {
        switch model.payload.networkState {
        case .ok: return ExoSentryTheme.primary
        case .lanLost, .wanLost: return .orange
        case .offline: return .red
        }
    }
}

// MARK: - Thunderbolt IP Card (local @State avoids ForEach+TextField re-render bug)

private struct ThunderboltIPCard: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var editEnabled: Bool = false
    @State private var editConfigs: [ThunderboltIPConfig] = []

    var body: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("雷电网络固定 IP", systemImage: "bolt.horizontal.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $editEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                ForEach($editConfigs) { $config in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $config.enabled)
                                .toggleStyle(.checkbox)
                            Text(config.service)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Text("IP:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            TextField("IP 地址", text: $config.ip)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 90, maxWidth: 110)
                            Text("子网:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("子网掩码", text: $config.subnet)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 100, maxWidth: 120)
                            Text("路由:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("可选", text: $config.router)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 70, maxWidth: 100)
                        }
                        .padding(.leading, 24)
                    }
                    .opacity(editEnabled && config.enabled ? 1.0 : 0.5)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启动应用时将自动应用此配置")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("IPv6 将自动设为仅本地链接")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("恢复默认") {
                        editConfigs = ThunderboltIPConfig.defaultConfigs
                    }
                    .controlSize(.small)
                    Button("应用配置") {
                        model.thunderboltIPEnabled = editEnabled
                        model.thunderboltIPConfigs = editConfigs
                        model.applyThunderboltIPConfigs()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(ExoSentryTheme.primary)
                    .disabled(!editEnabled)
                }

                if let warning = model.warningMessage, warning.contains("雷电") {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(warning.contains("失败") ? .red : ExoSentryTheme.primary)
                }
            }
        }
        .onAppear {
            editEnabled = model.thunderboltIPEnabled
            editConfigs = model.thunderboltIPConfigs
        }
    }
}

// MARK: - About Panel

private struct AboutPanel: View {
    @ObservedObject var model: MenuBarViewModel

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ExoSentry"
    }

    private var version: String {
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(ver) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(ExoSentryTheme.primary)

            Text(appName)
                .font(.title)
                .fontWeight(.bold)

            Text("版本 \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("ExoSentry 是一款 macOS 菜单栏守护应用，\n用于保障 Apple Silicon 算力集群节点持续在线。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Divider()
                .frame(width: 200)

            Button {
                model.openLogFile()
            } label: {
                Label("导出日志", systemImage: "doc.text")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Shared Card Component

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    ExoSentryTheme.primary.opacity(isHovered ? 0.3 : 0),
                    lineWidth: 1
                )
        )
        .shadow(color: ExoSentryTheme.primary.opacity(isHovered ? 0.08 : 0), radius: 8, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

private func settingsCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
    SettingsCard(content: content)
}

// MARK: - Hoverable Icon Button

private struct HoverableIconButton: View {
    let icon: String
    let color: Color
    let hoverColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(isHovered ? hoverColor : color)
                .font(.system(size: 16))
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
