# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

ExoSentry 是一款 macOS 菜单栏守护应用，用于保障 Apple Silicon 算力集群节点（如 EXO）持续在线。核心功能包括：防止系统休眠、合盖运行（Clamshell）、进程守护联动、断网重连、过热熔断保护、本地状态 API（localhost:1988/status）。

- 平台：macOS Ventura 13.0+，Apple Silicon arm64
- 语言：Swift 5.9+
- UI：SwiftUI 菜单栏应用（无窗口）

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
brew install xcodegen
Scripts/materialize_signing_requirements.sh
xcodegen generate --spec Xcode/project.yml

# MVP 验收检查
Scripts/mvp_acceptance.sh

# 发布安全加固检查
Scripts/release_hardening_check.sh
```

## 架构

### 模块依赖关系

```
ExoSentryApp（菜单栏应用，SwiftUI）
  ├── ExoSentryCore（核心业务逻辑，无 UI 依赖）
  └── ExoSentryXPC（XPC 特权通信桥接）
        └── ExoSentryCore

ExoSentryHelper（独立特权守护进程，root 权限运行）
```

App 与 Helper 之间通过 NSXPCConnection（Mach service: `com.exosentry.helper`）通信。Helper 通过 SMJobBless 安装为 LaunchDaemon。

### 关键组件流

**启动流程：** `ExoSentryMenuBarApp` → `MenuBarViewModel.start()` → `StartupRecoveryCoordinator.recoverOnLaunch()`（清除残留 pmset 状态）→ 启动 `LocalStatusServer` → 启动两个并发循环。

**守护循环（每 5 秒）：** `GuardRuntimeOrchestrator.runCycle()` 依次执行：
1. `ProcessMatcher` 检查目标进程是否运行
2. 进程运行时 → `PowerAssertionManager.activate()`（IOKit 断言）+ `GuardCoordinator.activate()`（通过 XPC 调用 `pmset -a disablesleep 1`）
3. `ConnectivityPolicyTracker` 评估网络状态
4. `ThermalProtectionController` 记录温度并评估是否触发熔断

**UI 刷新循环（每 1 秒）：** 从 `AppStateStore` 获取 `StatusPayload` 快照。

### 状态管理

`AppStateStore` 是一个 **actor**，是所有运行时状态的唯一数据源。通过 `snapshotStatus()` 生成 `StatusPayload`，供 UI 和 API 使用。权限警告（`PermissionWarningState.warning`）会强制将状态覆盖为 `.degraded`。

### XPC 特权操作分层

同一功能在不同层有不同实现，通过 `SleepSettingsControlling` 协议抽象：
- **App 侧：** `PrivilegedSleepSettingsController` → 通过 `PrivilegedXPCClient` 转发
- **Helper 侧：** `HelperSleepSettingsController` → 直接执行 `pmset`
- **测试中：** 注入 Stub/Spy 替代

### 协议驱动的依赖注入

所有外部依赖通过协议定义，在 `RuntimeDependencies` 结构体中聚合注入到 `GuardRuntimeOrchestrator`：
- `ProcessSnapshotProviding` — 进程快照
- `NetworkProbing` — 网络探测
- `TemperatureProviding` — 温度读取
- `PowerAssertionManaging` — IOKit 电源断言
- `SleepSettingsControlling` — 睡眠设置（经 `GuardCoordinator` 包装）

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

## 安全注意事项

- `pmset`、Wi-Fi 控制等特权操作只能通过 Helper Tool 执行，不能在 App 层直接调用
- 本地状态 API 必须保持 localhost-only（`isLoopback` 检查），不暴露特权内部状态
- 发布前需运行 `Scripts/materialize_signing_requirements.sh` 配置 Team ID 签名要求
- 发布检查清单见 `Xcode/RELEASE.md`
