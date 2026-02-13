import ExoSentryCore
import SwiftUI

struct MenuBarDropdownView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Status Header
            statusHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // MARK: - Monitoring Info
            monitoringSection
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            sectionDivider

            // MARK: - Controls
            controlsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            sectionDivider

            // MARK: - API Endpoint
            apiEndpointSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            sectionDivider

            // MARK: - Warning Messages
            if model.payload.status == .degraded {
                warningRow(text: "权限异常", buttonTitle: "一键修复") {
                    model.repairPrivileges()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                sectionDivider
            }

            if model.payload.status == .overheatTrip {
                warningRow(text: "高温已熔断", buttonTitle: "手动恢复") {
                    model.confirmThermalRecovery()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                sectionDivider
            }

            if let warning = model.warningMessage {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(warning.contains("已") ? ExoSentryTheme.primary : .red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                sectionDivider
            }

            if let batteryWarning = model.batteryHealthMessage {
                HStack(spacing: 6) {
                    Image(systemName: "battery.75")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(batteryWarning)
                        .font(.system(size: 10))
                        .foregroundStyle(ExoSentryTheme.Popover.textSecondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                sectionDivider
            }

            // MARK: - Menu Actions
            menuActions
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .padding(.bottom, 4)
        }
        .frame(width: 300)
        .background(ExoSentryTheme.Popover.background)
        .onAppear {
            model.start()
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            HStack(spacing: 8) {
                PulsingStatusDot(status: model.payload.status)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("状态:")
                            .font(.system(size: 13, weight: .medium))
                        Text(model.payload.status.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        if model.payload.lidClosed {
                            Text("(已合盖)")
                                .font(.system(size: 11))
                                .foregroundStyle(ExoSentryTheme.Popover.textSecondary)
                        }
                    }
                }
            }
            Spacer()
            if model.payload.status == .active {
                Text("哨兵节点")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ExoSentryTheme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ExoSentryTheme.primary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
    }

    // MARK: - Monitoring Section

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text("SoC 温度:")
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11))
                }
                Spacer()
                if let temp = model.payload.tempC {
                    Text("\(Int(temp))°C")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                } else {
                    Text("--")
                        .font(.system(size: 12))
                        .foregroundStyle(ExoSentryTheme.Popover.textTertiary)
                }
            }

            HStack {
                Label {
                    Text("负载:")
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(model.loadLevel.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.loadLevel.color)
                    if model.loadLevel == .high || model.loadLevel == .extreme {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("合盖模式")
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                        .font(.system(size: 11))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.isClamshellEnabled },
                    set: { model.setClamshellMode($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            HStack {
                Label {
                    HStack(spacing: 4) {
                        Text(model.payload.targetProcess)
                            .font(.system(size: 12))
                        Text(model.payload.targetProcessRunning ? "(运行中)" : "(已停止)")
                            .font(.system(size: 11))
                            .foregroundStyle(model.payload.targetProcessRunning
                                ? ExoSentryTheme.primary
                                : ExoSentryTheme.Popover.textTertiary)
                    }
                } icon: {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 11))
                }
                Spacer()
                if model.autoRestartEnabled && !model.payload.targetProcessRunning {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("自动重启")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(ExoSentryTheme.primary.opacity(0.8))
                }
            }
        }
        .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
    }

    // MARK: - API Endpoint Section

    private var apiEndpointSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本地 API 端点")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ExoSentryTheme.Popover.textTertiary)
            HStack {
                Text(model.apiEndpointURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ExoSentryTheme.Popover.textSecondary)
                Spacer()
                HoverableCopyButton {
                    model.copyAPIEndpoint()
                }
            }
        }
    }

    // MARK: - Warning Row

    private func warningRow(text: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
            Spacer()
            Button(buttonTitle) {
                action()
            }
            .font(.system(size: 11))
            .controlSize(.small)
        }
    }

    // MARK: - Menu Actions

    private var menuActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    settingsLinkLabel
                }
                .buttonStyle(.plain)
                .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
                .hoverHighlight()
            } else {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    settingsLinkLabel
                }
                .buttonStyle(.plain)
                .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
                .hoverHighlight()
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text("退出 ExoSentry")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\u{2318}Q")
                        .font(.system(size: 12))
                        .foregroundStyle(ExoSentryTheme.Popover.textTertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ExoSentryTheme.Popover.textPrimary)
            .hoverHighlight()
        }
    }

    private var settingsLinkLabel: some View {
        HStack {
            Text("首选项...")
                .font(.system(size: 13))
            Spacer()
            Text("\u{2318},")
                .font(.system(size: 12))
                .foregroundStyle(ExoSentryTheme.Popover.textTertiary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider()
            .background(ExoSentryTheme.Popover.sectionDivider)
    }
}

// MARK: - Hoverable Copy Button

private struct HoverableCopyButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? ExoSentryTheme.primary : ExoSentryTheme.Popover.textSecondary)
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Pulsing Status Dot

struct PulsingStatusDot: View {
    let status: GuardStatus
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if status == .active {
                Circle()
                    .fill(ExoSentryTheme.statusActive.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }
            Circle()
                .fill(status.statusColor)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            if status == .active {
                isPulsing = true
            }
        }
        .onChange(of: status) { newStatus in
            isPulsing = newStatus == .active
        }
    }
}
