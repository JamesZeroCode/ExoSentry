# AGENTS.md

This file guides coding agents working in `ExoSentry`.

## 1) Repository Reality (Current State)

- Current repository contains product documentation only.
- Verified primary file: `ExoSentry-prd.md`.
- No Swift source files found (`*.swift`, `Package.swift`, `.xcodeproj`, `.xcworkspace` are absent).
- No CI/build config found (`Makefile`, `justfile`, `package.json`, `pyproject.toml`, etc. are absent).
- No Cursor rule files found:
  - `.cursorrules` not found.
  - `.cursor/rules/` not found.
- No Copilot instruction file found:
  - `.github/copilot-instructions.md` not found.

Implication: there are no repo-enforced executable commands yet.

## 2) Source of Truth

Until implementation starts, `ExoSentry-prd.md` is the single source of truth.

Key constraints extracted from PRD:

- Platform: macOS Ventura 13.0+, Apple Silicon arm64.
- Language: Swift 5.9+.
- UI: SwiftUI menu bar app.
- Power management: IOKit + `ProcessInfo.activity`.
- Privileged operations: Helper Tool + XPC.
- Optional local HTTP status API (`/status`), with low overhead.
- Security-sensitive operations (`pmset`, network recovery) must be privileged and explicit.

## 3) Build / Lint / Test Commands

### 3.1 Repo-Verified Commands (as of now)

- Build: not defined in repository.
- Lint: not defined in repository.
- Test: not defined in repository.
- Single-test command: not defined in repository.

Do not claim commands are available unless the corresponding project files exist.

### 3.2 Fallback Commands for Future Swift Setup

Use these only after confirming project type.

#### A) If this becomes a Swift Package (SPM)

- Build:
  - `swift build`
- Test all:
  - `swift test`
- Run a single test target (all tests in target):
  - `swift test --filter <TestTargetName>`
- Run a single test class/suite:
  - `swift test --filter <TestCaseClassName>`
- Run a single test method:
  - `swift test --filter <TestCaseClassName>/<testMethodName>`
- `--filter` format can vary slightly by toolchain; verify with `swift test --help`.

#### B) If this becomes an Xcode project/workspace

- List schemes:
  - `xcodebuild -list -project ExoSentry.xcodeproj`
  - or `xcodebuild -list -workspace ExoSentry.xcworkspace`
- Build:
  - `xcodebuild -scheme ExoSentry -destination 'platform=macOS' build`
- Test all:
  - `xcodebuild -scheme ExoSentry -destination 'platform=macOS' test`
- Run one test class:
  - `xcodebuild -scheme ExoSentry -destination 'platform=macOS' -only-testing:ExoSentryTests/<TestCaseClassName> test`
- Run one test method:
  - `xcodebuild -scheme ExoSentry -destination 'platform=macOS' -only-testing:ExoSentryTests/<TestCaseClassName>/<testMethodName> test`
- Keep scheme and test bundle names synchronized with project settings.
- Prefer explicit destination for reproducibility.

### 3.3 Lint/Format Recommendations (optional)

- SwiftFormat:
  - `swiftformat .`
- SwiftLint:
  - `swiftlint`
  - `swiftlint lint --strict`

If lint tools are not configured in-repo, treat them as local checks only.

## 4) Coding Style Guidelines (Project-Specific Defaults)

These are inferred from PRD architecture and should be applied consistently when code is added.

### 4.1 Imports and Module Boundaries

- Keep imports minimal and file-local.
- Prefer Apple frameworks first: `SwiftUI`, `Foundation`, `IOKit`, `Network`.
- Isolate privileged operations behind XPC interfaces; do not call privileged shell commands directly from UI layer.
- Keep API-server concerns separated from power-management concerns.

### 4.2 Formatting

- Use standard Swift formatting conventions.
- Keep one primary type per file for readability.
- Prefer small focused files over giant multi-responsibility files.
- Wrap long argument lists one-per-line when line length harms readability.

### 4.3 Types and Safety

- Prefer strong typing over stringly-typed state.
- Model daemon/app state with enums (e.g., active, paused, overheating, degraded).
- Avoid force unwraps in production paths.
- Use `Result` or typed errors across boundary operations (XPC, process management, API responses).

### 4.4 Naming Conventions

- Types: `UpperCamelCase` (`PowerAssertionManager`).
- Methods/properties/variables: `lowerCamelCase` (`startGuardMode`).
- Boolean names should read as predicates (`isCharging`, `isLidClosed`, `hasRootPrivilege`).
- Test names should describe behavior (`testStopsMiningWhenTemperatureExceedsThreshold`).

### 4.5 Error Handling

- Never swallow errors silently.
- Include actionable context in logs (`operation`, `component`, `reason`, `recoveryHint`).
- For privileged failures, return user-safe messages and keep technical detail in logs.
- For retry loops (network recovery), enforce backoff and max-attempt policy.

### 4.6 Concurrency and Resource Use

- Keep monitoring loops lightweight; PRD target is very low overhead.
- Avoid busy-wait polling; use timers/observers/events where possible.
- Ensure thread-safe state transitions for watchdog and thermal protection.
- Prefer structured concurrency for async workflows.

### 4.7 Security and Privilege Separation

- Treat `pmset` and Wi-Fi control as sensitive operations.
- Keep least-privilege boundaries strict: UI app unprivileged, helper privileged.
- Validate and sanitize any user-configurable process names or command inputs.
- Never expose privileged internals through the local status API.

### 4.8 Testing Priorities

- Unit test state transitions (guard on/off, process found/lost, overheat trip/recover).
- Unit test error paths for helper communication and permission loss.
- Add integration tests for status API payload shape and status correctness.
- Add regression tests for lid-closed and reconnect scenarios when feasible.

## 5) Agent Operating Rules for This Repo

- Do not invent non-existent commands as "project commands".
- Clearly separate "verified in repo" vs "fallback/default".
- If Cursor/Copilot rules are added later, update this file immediately.
- Prefer minimal changes aligned with PRD priorities (P0 -> P1 -> P2).
- Flag safety risks when touching thermal, battery, sleep, or privileged behavior.

## 6) Future Update Checklist (When Code Appears)

Update this file after first implementation PR with:

- Exact build/test/lint commands from real project files.
- Exact single-test invocation that works in CI.
- Concrete style/lint configs and test folder conventions.
- Any new `.cursor` or `.github` agent instruction files.
