# AGENTS.md

本文件为在 `ExoSentry` 仓库工作的 agent（含代码代理）提供可执行、可验证的工程规范。

## 1. 仓库现状（已实现）

- 当前是 Swift 5.9 项目，支持 macOS 13.0+（Apple Silicon）。
- 已存在 SPM 清单：`Package.swift`。
- 已存在 Xcode 工程与 XcodeGen 规格：`Xcode/ExoSentry.xcodeproj`、`Xcode/project.yml`。
- 主要模块：
  - `Sources/ExoSentryApp`（菜单栏应用）
  - `Sources/ExoSentryCore`（核心逻辑）
  - `Sources/ExoSentryXPC`（XPC 客户端桥接）
  - `Sources/ExoSentryHelper`（特权 Helper）
- 测试目录：
  - `Tests/ExoSentryCoreTests`
  - `Tests/ExoSentryXPCTests`

## 2. 规则文件检查（Cursor/Copilot）

经仓库扫描，当前不存在以下文件：
- `.cursorrules`
- `.cursor/rules/`
- `.github/copilot-instructions.md`

若后续新增上述规则文件，必须同步更新本 AGENTS.md。

## 3. Build / Lint / Test 命令（仓库可验证）

### 3.1 SPM 常用命令（推荐默认）

- 构建：
  - `swift build`
- 全量测试：
  - `swift test`

### 3.2 运行单个测试（重点）

- 单个 test target：
  - `swift test --filter ExoSentryCoreTests`
  - `swift test --filter ExoSentryXPCTests`
- 单个测试类：
  - `swift test --filter GuardCoordinatorTests`
- 单个测试方法：
  - `swift test --filter "GuardCoordinatorTests/testActivateClusterAppliesClamshell"`

说明：`--filter` 的匹配行为会随 toolchain 略有差异，异常时先执行 `swift test --help` 确认格式。

### 3.3 工程脚本

- MVP 验收清单：
  - `Scripts/mvp_acceptance.sh`
- 发布前安全加固检查：
  - `Scripts/release_hardening_check.sh`
- 资源基线检查（NF-01）：
  - `Scripts/performance_baseline_check.sh ExoSentryApp`
  - 可选阈值变量：
    - `EXOSENTRY_CPU_THRESHOLD=0.5`
    - `EXOSENTRY_MEMORY_THRESHOLD_MB=50`
    - `EXOSENTRY_SAMPLE_COUNT=5`

### 3.4 Xcode / XcodeGen 命令

- 生成（或更新）Xcode 工程：
  - `xcodegen generate --spec Xcode/project.yml --project Xcode`
- 查看 scheme：
  - `xcodebuild -list -project Xcode/ExoSentry.xcodeproj`

注意：新增/删除 Swift 文件后，SPM 自动发现源文件，但 Xcode 工程需要重新 `xcodegen generate`。

### 3.5 Lint / Format（仓库未强制）

- 仓库未配置强制 SwiftLint/SwiftFormat。
- 可选本地命令（若本机安装）：
  - `swiftlint`
  - `swiftformat .`

## 4. 代码风格与工程约定

### 4.1 Imports 与模块边界

- import 最小化：每个文件仅引入需要的模块。
- 常见顺序：先本地模块，再 Apple 框架（如 `Foundation`、`SwiftUI`）。
- UI 层不得直接执行特权命令（如 `pmset`、`networksetup`）；必须经 XPC -> Helper。
- `Core` 尽量保持无 UI 依赖。

### 4.2 格式化

- 使用标准 Swift 风格：4 空格缩进，长参数列表按行拆分。
- 倾向单一职责：一个文件围绕一个核心类型或一组紧密相关类型。
- 公共 API 的 `init`、`enum`、`protocol` 保持清晰显式。

### 4.3 类型系统与并发

- 协议优先 + 依赖注入（见 `RuntimeDependencies`）。
- 需要跨并发域的协议/模型尽量标记 `Sendable`。
- 引入锁保护的引用类型可使用 `@unchecked Sendable`，但必须有明确同步策略（如 `NSLock`）。
- 阻塞调用（外部进程/XPC wait）不要占用 cooperative pool，按现有模式迁移到独立队列。

### 4.4 命名规范

- 类型：`UpperCamelCase`（例：`GuardRuntimeOrchestrator`）。
- 变量/方法：`lowerCamelCase`（例：`updateThermalPolicy`）。
- Bool 命名使用谓词语义：`isCharging`、`shouldProbeNetworkNow`。
- 测试名使用行为描述：`testXxxWhenYyy`。

### 4.5 错误处理与日志

- 不吞错：出现错误至少返回、抛出或记录日志。
- 错误类型优先使用强类型 enum（如 `PrivilegedClientError`）。
- 用户可见文案与技术细节分离：
  - UI 展示安全、可理解信息
  - 技术细节写入日志（operation + message + metadata）
- 重试逻辑需有上限与退避，不允许无限重试。

### 4.6 安全与特权边界

- 所有敏感系统操作必须在 Helper 执行。
- XPC 协议保持双端镜像一致：
  - `Sources/ExoSentryHelper/HelperXPCProtocol.swift`
  - `Sources/ExoSentryXPC/HelperXPCProtocol.swift`
- 本地状态 API 保持 localhost-only，不暴露特权内部细节。
- 发布前执行签名与授权校验脚本。

### 4.7 SwiftUI 约定

- `MenuBarExtra` 的样式和状态图标语义应与业务状态严格对齐。
- 重要状态（active/paused/overheat/degraded）需同时具备文本语义与视觉语义。
- 设置项变更应立即作用于 runtime，并优先支持持久化。

### 4.8 测试约定

- 单元测试中优先使用 Stub/Spy 隔离外部依赖。
- Core 侧重点：状态机、策略、序列化、网络/热保护判定。
- XPC 侧重点：权限状态流转、调用转发、失败路径。
- 新增功能必须至少包含：
  - 1 条成功路径测试
  - 1 条失败/边界路径测试

## 5. Agent 执行守则（本仓库）

- 只声明“仓库可验证”的命令，不要编造命令。
- 修改涉及特权/热保护/网络恢复时，优先做最小变更，避免顺手重构。
- 变更后至少做：
  - 受影响文件的诊断检查
  - `swift test`
- 变更需求追踪后，需同步更新 `PRD-功能追踪表.csv`。

## 6. 常见任务速查

- 我只想跑某个测试：
  - `swift test --filter "ClassName/testMethod"`
- 我改了文件但 Xcode 没看到：
  - 重新执行 `xcodegen generate --spec Xcode/project.yml --project Xcode`
- 我在改 Helper/XPC 协议：
  - 先改双端协议文件，再改 client/service，再补测试

## 7. 后续维护清单

当项目结构变化时，优先更新本文件中的：
- build/test/单测命令
- 模块关系和边界规则
- 代码风格与测试准入要求
- Cursor/Copilot 规则状态
