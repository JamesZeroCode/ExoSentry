# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

ExoSentry 是一款 macOS 菜单栏守护应用，用于保障 Apple Silicon 算力集群节点（如 EXO）持续在线。核心功能包括：防止系统休眠、合盖运行（Clamshell）、进程守护联动、自动重启、断网重连、过热熔断保护、雷电口固定 IP、本地状态 API（localhost:1988/status）。

- 平台：macOS Ventura 13.0+，Apple Silicon arm64
- 语言：Swift 5.9+
- UI：SwiftUI 菜单栏应用（MenuBarExtra + Settings 窗口）

## 构建与测试命令

```bash
# 构建（SPM）
swift build

# 运行全部测试
swift test

# 运行单个测试 target
swift test --filter ExoSentryCoreTests
swift test --filter ExoSentryXPCTests

# 运行单个测试方法
swift test --filter "GuardCoordinatorTests/testActivateCallsSetDisableSleep"

# 生成 Xcode 项目（需要 xcodegen）
xcodegen generate --spec Xcode/project.yml --project Xcode

# MVP 验收检查
Scripts/mvp_acceptance.sh

# 发布安全加固检查
Scripts/release_hardening_check.sh
```

**重要：** 新增/删除 Swift 源文件后必须重新运行 `xcodegen generate --spec Xcode/project.yml --project Xcode` 以更新 Xcode 项目。SPM 自动扫描 Sources 目录，但 Xcode 项目需要重新生成。

## 架构

### 模块依赖关系

```
ExoSentryApp（菜单栏应用，SwiftUI）
  ├── ExoSentryCore（核心业务逻辑，无 UI 依赖）
  └── ExoSentryXPC（XPC 特权通信桥接）
        └── ExoSentryCore

ExoSentryHelper（独立特权守护进程，root 权限运行）
```

App 与 Helper 之间通过 NSXPCConnection（Mach service: `com.exosentry.helper`）通信。Helper 通过 SMAppService.daemon() 安装为 LaunchDaemon（安装到 `/Library/PrivilegedHelperTools/com.exosentry.helper`）。

### UI 层结构

```
Sources/ExoSentryApp/
├── ExoSentryMenuBarApp.swift       # @main 入口，MenuBarExtra(.window) + Settings
├── MenuBarViewModel.swift          # ViewModel：生命周期、设置应用、UserDefaults 持久化
├── MenuBarDropdownView.swift       # 菜单栏弹窗（深色主题、脉冲动画）
├── PreferencesView.swift           # 偏好设置（侧边栏导航 + 5 个面板，含 Swift Charts）
├── ExoSentryTheme.swift            # 品牌配色常量、LoadLevel 枚举
└── ModelDisplayExtensions.swift    # GuardStatus/OperatingMode/NetworkState 的 displayName/statusColor/iconName
```

`MenuBarExtra` 必须使用 `.menuBarExtraStyle(.window)` 才能渲染自定义 SwiftUI 视图。偏好设置使用自定义侧边栏导航（非 TabView），打开方式通过 `SettingsLink`（macOS 14+）或 `NSApp.sendAction` 回退。

### 关键组件流

**启动流程：** `ExoSentryMenuBarApp` → `MenuBarViewModel.start()` → `StartupRecoveryCoordinator.recoverOnLaunch()`（清除残留 pmset 状态）→ 应用雷电 IP 配置（若启用）→ 启动 `LocalStatusServer` → 启动守护循环。

**守护循环（每 5 秒）：** `GuardRuntimeOrchestrator.runCycle()` 依次执行：
1. `ProcessMatcher` 检查目标进程是否运行
2. 进程运行时 → `PowerAssertionManager.activate()`（IOKit 断言）+ `GuardCoordinator.activate()`（通过 XPC 调用 `pmset -a disablesleep 1`）
3. 进程未运行且自动重启已启用 → 尝试重启（15秒冷却，3次失败后触发完整重启）
4. `ConnectivityPolicyTracker` 评估网络状态
5. `ThermalProtectionController` 记录温度并评估是否触发熔断

### 状态管理

`AppStateStore` 是一个 **actor**，是所有运行时状态的唯一数据源。通过 `snapshotStatus()` 生成 `StatusPayload`，供 UI 和 API 使用。权限警告（`PermissionWarningState.warning`）会强制将状态覆盖为 `.degraded`。

### 设置持久化

`MenuBarViewModel` 使用 UserDefaults 持久化以下设置（应用重启后恢复）：

| Key | 内容 | 默认值 |
|-----|------|--------|
| `ExoSentry.operatingMode` | 运行模式 (cluster/standard) | standard |
| `ExoSentry.targetProcesses` | 目标进程列表 (逗号分隔) | exo |
| `ExoSentry.thermalThreshold` | 温度阈值 (°C) | 95 |
| `ExoSentry.apiPort` | API 端口 | 1988 |
| `ExoSentry.autoRestartEnabled` | 自动重启开关 | false |
| `ExoSentry.launchCommand` | 重启时执行的命令 | "" |
| `ExoSentry.thunderboltIPEnabled` | 雷电 IP 配置开关 | false |
| `ExoSentry.thunderboltIPConfigs` | 雷电 IP 配置 (JSON Data) | 默认4口配置 |

`init()` 读取持久化值并用其初始化 `AppStateStore` 和 `GuardRuntimeOrchestrator`。各 `apply*()` 方法在应用设置时自动保存。

### XPC 特权操作分层

同一功能在不同层有不同实现，通过协议抽象：
- **App 侧：** `PrivilegedXPCClient`（实现 `PrivilegedCommanding`）→ 通过 NSXPCConnection 转发到 Helper
- **Helper 侧：** `HelperService`（实现 `ExoSentryHelperXPCProtocol`）→ 调用各 Controller 直接执行系统命令
- **测试中：** 注入 Stub/Spy 替代 `PrivilegedCommanding`

### 添加新 XPC 方法的完整流程

XPC 协议文件存在**两份镜像**（因为 Helper 和 App 是独立编译 target），修改时必须同步更新：

1. `Sources/ExoSentryHelper/HelperXPCProtocol.swift` — 添加 `@objc` 方法签名（参数用 `NSString` 等 ObjC 类型）
2. `Sources/ExoSentryXPC/HelperXPCProtocol.swift` — **镜像**同一协议定义
3. `Sources/ExoSentryXPC/PrivilegedCommanding.swift` — 添加 Swift 风格的 `throws` 方法
4. `Sources/ExoSentryXPC/PrivilegedXPCClient.swift` — 实现调用（使用 `performVoidOperation`）
5. `Sources/ExoSentryHelper/HelperService.swift` — 注入对应 Controller 并实现方法（遵循 do/catch + `markPrivilegeState` 模式）
6. Helper 侧新建 Controller（如 `HelperNetworkIPController.swift`）执行实际系统命令
7. **更新所有测试中的 `PrivilegedCommanding` Spy/Stub** — 添加新方法的空实现

**关键：** 修改 XPC 协议后，已安装的 Helper 守护进程需要更新。开发环境中手动更新：
```bash
sudo cp .build/arm64-apple-macosx/debug/ExoSentryHelper /Library/PrivilegedHelperTools/com.exosentry.helper
sudo launchctl bootout system/com.exosentry.helper 2>/dev/null
sudo launchctl bootstrap system /Library/LaunchDaemons/com.exosentry.helper.plist
```

### 协议驱动的依赖注入

所有外部依赖通过协议定义，在 `RuntimeDependencies` 结构体中聚合注入到 `GuardRuntimeOrchestrator`：
- `ProcessSnapshotProviding` — 进程快照
- `NetworkProbing` — 网络探测
- `TemperatureProviding` — 温度读取
- `PowerAssertionManaging` — IOKit 电源断言
- `SleepSettingsControlling` — 睡眠设置（经 `GuardCoordinator` 包装）
- `ProcessControlling` — 进程启动/终止（自动重启用）
- `AppNapActivityManaging` — 防止 App Nap 冻结

所有协议均标记 `Sendable`。需要内部同步的类使用 `@unchecked Sendable` + `NSLock`。

### Bundle IDs

- App: `com.exosentry.app`
- Core: `com.exosentry.core`
- XPC: `com.exosentry.xpc`
- Helper: `com.exosentry.helper`

## 测试约定

- 使用 **Spy**（跟踪调用计数/参数）和 **Stub**（返回预设值）模式，定义在各测试文件的 `private` 类型中
- `LocalStatusServerTests` 验证 localhost-only 安全策略（非回环地址返回 403）
- `StatusPayload` 的 JSON 序列化使用 snake_case（通过 CodingKeys 映射，如 `tempC` → `temp_c`）

## SwiftUI 已知坑点

- **ForEach + TextField + @Published 数组**：在 `ForEach($model.publishedArray)` 中使用 TextField 会因每次键入触发 `objectWillChange` 导致视图重建、光标丢失。**解决方案**：将编辑区域提取为独立视图，使用 `@State` 本地副本编辑，点按钮时再同步回 model（参见 `ThunderboltIPCard` 实现）。
- `MenuBarExtra` 必须使用 `.menuBarExtraStyle(.window)` 才能渲染自定义 SwiftUI 视图。

## macOS 版本兼容注意事项

部署目标为 macOS 13.0，使用以下 API 时需做版本检查：
- `SettingsLink` — macOS 14+，回退到 `NSApp.sendAction(Selector("showSettingsWindow:"))`
- `.background(.background.secondary)` — macOS 14+，使用 `Color(nsColor: .controlBackgroundColor)` 替代
- Swift Charts (`import Charts`) — macOS 13+ 内置，无需额外依赖

## 安全注意事项

- `pmset`、Wi-Fi 控制、`networksetup` 等特权操作只能通过 Helper Tool 执行，不能在 App 层直接调用
- 本地状态 API 必须保持 localhost-only（`isLoopback` 检查），不暴露特权内部状态
- 发布前需运行 `Scripts/materialize_signing_requirements.sh` 配置 Team ID 签名要求
- 发布检查清单见 `Xcode/RELEASE.md`
