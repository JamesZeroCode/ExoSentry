

# ExoSentry - macOS 算力集群节点守护者 PRD

**版本号:** v1.0

**状态:** 开发中

**最后更新:** 2026-02-09

---

## 1. 项目背景与目标 (Background & Goals)

### 1.1 背景

构建基于 macOS（特别是 Apple Silicon M1/M2/M3）的 EXO 算力集群时，面临系统自带的激进节能策略挑战：

* **自动休眠/锁屏：** 导致计算中断，节点在网络中下线。
* **合盖即挂起：** MacBook 在不接外接显示器的情况下，合盖会强制休眠，无法堆叠部署。
* **网络断连：** 后台运行时 Wi-Fi 可能会进入低功耗模式，导致心跳丢失。

### 1.2 目标

开发一款名为 **ExoSentry** 的 macOS 菜单栏应用，实现：

1. **绝对在线：** 只要接通电源，强制系统、硬盘、网络处于活跃状态。
2. **无头模式支持 (Headless)：** 支持 MacBook 在未连接显示器的情况下合盖运行。
3. **进程守护：** 监控算力程序（如 `exo`），确保其持续运行。
4. **集群监控：** 提供轻量级 API 供外部监控系统读取状态。

---

## 2. 用户角色 (User Roles)

| 角色 | 描述 | 核心诉求 |
| --- | --- | --- |
| **集群管理员 (你)** | 拥有多台 Mac 设备，需要批量管理。 | 稳定第一，不仅要防休眠，还要能自动恢复。 |
| **单节点矿工** | 使用个人 Mac 闲置算力。 | 简单易用，不想输入复杂命令行，不影响日常使用。 |

---

## 3. 功能需求 (Functional Requirements)

### 3.1 核心电源管理 (Power Management) - P0 (最高优先级)

| ID | 功能名称 | 详细描述 | 验收标准 |
| --- | --- | --- | --- |
| **F-01** | **强制唤醒断言** | 启动时向 macOS 内核发送 `kIOPMAssertionTypeNoIdleSleep` 和 `kIOPMAssertionTypeNoDisplaySleep`。 | 开启软件后，即使无键鼠操作，系统永不休眠，屏幕永不锁屏。 |
| **F-02** | **合盖运行模式 (Clamshell)** | 允许 MacBook 在无外接显示器时合盖运行。实现逻辑：通过 Helper Tool 调用 `pmset -a disablesleep 1`。 | 拔掉外接显示器 -> 合上 MacBook 盖子 -> SSH 连接依然通畅，EXO 任务不中断。 |
| **F-03** | **防 App Nap** | 针对 `exo` 核心进程申请 `NSProcessInfo` 活动令牌，防止系统将其降级为低功耗模式。 | 即使 ExoSentry 在后台，算力哈希率（Hashrate）不下降。 |

### 3.2 进程与自动化 (Process & Automation) - P1

| ID | 功能名称 | 详细描述 | 验收标准 |
| --- | --- | --- | --- |
| **F-04** | **开机自启** | 利用 `SMAppService` 注册为登录项。 | 重启 Mac 后，软件自动启动并进入“守护模式”。 |
| **F-05** | **智能进程联动** | 用户可配置目标进程名（如 `python3`, `exo-node`）。仅当检测到该进程运行时，才激活防休眠；否则保持系统默认。 | 检测到 `exo` 启动 -> 自动阻止休眠；`exo` 退出 -> 自动恢复休眠设置。 |
| **F-06** | **断网重连守护** | 定时（每 60秒）ping 网关。如果失败，尝试通过 shell 命令重启 Wi-Fi 接口（需 Root 权限）。 | 模拟断网后，软件能自动尝试恢复网络连接。 |

### 3.3 监控与 API (Monitoring) - P2

| ID | 功能名称 | 详细描述 | 验收标准 |
| --- | --- | --- | --- |
| **F-07** | **本地状态 API** | 内置微型 HTTP 服务器，暴露 `http://localhost:1988/status`。返回 JSON：CPU 温度、是否在充电、EXO 进程状态。 | 访问 URL 能获取到 `{ "status": "active", "temp": 65, "lid_closed": true }`。 |
| **F-08** | **过热熔断保护** | 当监测到 SoC 温度 > 95°C 持续 1 分钟，自动终止算力进程并允许系统风扇全速运转。 | 高温工况下，软件主动停止任务以保护硬件。 |

---

## 4. 非功能需求 (Non-Functional Requirements)

* **性能要求：** 软件自身 CPU 占用率需 < 0.5%，内存占用 < 50MB。不能抢占算力资源。
* **安全性：** 修改系统底层参数（如 `pmset`）的操作必须通过特权分离（Privileged Helper Tool）进行，符合 Apple 安全规范。
* **兼容性：** 必须原生支持 Apple Silicon (arm64)，最低兼容 macOS Ventura (13.0)。

---

## 5. UI/UX 设计 (User Interface)

### 5.1 菜单栏设计 (Menu Bar)

这是一个“无窗口”应用，主要交互在菜单栏图标：

* **图标状态：**
* 🟢 (绿点)：守护中，系统不会休眠。
* 🔴 (红点)：暂停守护，系统按默认设置运行。
* 🔥 (火苗)：检测到算力负载高。


* **下拉菜单项：**
* `Status: Active (Lid Closed)`
* `Mode: Cluster Mode / Standard Mode`
* `Target Process: exo (Running)`
* `Preferences...`
* `Quit`



### 5.2 设置面板 (Preferences Window)

* **General:** 开机自启开关。
* **Triggers:** 输入需要监控的进程名称列表。
* **Protection:** 设置温度阈值（例如 90°C 报警）。
* **Network:** 设置 API 端口号。

---

## 6. 技术架构与实现路径

### 6.1 架构图示

```mermaid
graph TD
    A[用户界面 (UI/Menu Bar)] --> B[应用主逻辑 (Swift)]
    B --> C{特权帮助程序 (Helper Tool)}
    C -- Root权限 --> D[pmset 系统命令]
    C -- Root权限 --> E[Wi-Fi 接口控制]
    B --> F[IOKit 电源断言]
    B --> G[HTTP Server (Swifter/Vapor)]
    B --> H[系统监控 (IOHID - 温度/风扇)]

```

### 6.2 关键技术栈

* **语言:** Swift 5.9+
* **UI:** SwiftUI (轻量级)
* **进程通信:** XPC Services (App 与 Helper Tool 通信)
* **电源管理:** `IOKit.framework`, `ProcessInfo.activity`
* **网络框架:** `Network.framework` (用于监测), `Swifter` (用于轻量级 HTTP API)

---

## 7. 风险与对策 (Risks)

| 风险点 | 影响 | 对策 |
| --- | --- | --- |
| **屏幕损坏** | MacBook M1 Pro 闭盖高负载会导致屏幕受热变黄甚至涂层脱落。 | **必须**在软件内添加显著的免责声明，建议用户使用“微开”支架或散热底座。 |
| **电池鼓包** | 长期插电且高温运行。 | 集成 macOS 的 `Optimized Battery Charging` 状态监测，建议用户使用 AlDente 等限制充电阈值工具配合。 |
| **权限丢失** | macOS 更新可能重置 `pmset` 权限。 | 每次启动时自检权限，若丢失则弹窗提示输入密码修复。 |

---

## 8. 开发路线图 (Roadmap)

* **Phase 1 (MVP - 3天):** 实现菜单栏 App，基础的防止休眠（IOKit），以及手动开关“闭盖模式”（pmset 封装）。
* **Phase 2 (Automation - 1周):** 加入进程监控（检测 `exo`），实现开机自启。
* **Phase 3 (Cluster Ready - 2周):** 开发 HTTP API 接口，实现温度监控和过热保护。

---
