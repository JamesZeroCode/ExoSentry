#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/.artifacts"
STATE_FILE="$ARTIFACT_DIR/reboot_validation_state.env"
REPORT_FILE="$ARTIFACT_DIR/reboot_validation_report.md"
APP_BUNDLE_ID="com.exosentry.app"

mkdir -p "$ARTIFACT_DIR"

read_default() {
  local key="$1"
  /usr/bin/defaults read "$APP_BUNDLE_ID" "$key" 2>/dev/null || true
}

collect_login_item_registered() {
  if /usr/bin/sfltool dumpbtm 2>/dev/null | /usr/bin/grep -q "Bundle Identifier: $APP_BUNDLE_ID"; then
    echo "true"
  else
    echo "false"
  fi
}

collect_process_running() {
  if /usr/bin/pgrep -f "ExoSentryApp|ExoSentry" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

collect_boot_epoch() {
  /usr/bin/python3 - <<'PY'
import subprocess
import re

out = subprocess.check_output(["/usr/sbin/sysctl", "-n", "kern.boottime"], text=True)
match = re.search(r"sec\s*=\s*(\d+)", out)
print(match.group(1) if match else "0")
PY
}

snapshot() {
  local boot_epoch
  boot_epoch="$(collect_boot_epoch)"

  cat >"$STATE_FILE" <<EOF
SNAPSHOT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SNAPSHOT_BOOT_EPOCH=$boot_epoch
SNAPSHOT_LOGIN_ITEM_REGISTERED=$(collect_login_item_registered)
EXPECTED_OPERATING_MODE=$(read_default ExoSentry.operatingMode)
EXPECTED_TARGET_PROCESSES=$(read_default ExoSentry.targetProcesses)
EXPECTED_THERMAL_THRESHOLD=$(read_default ExoSentry.thermalThreshold)
EXPECTED_API_PORT=$(read_default ExoSentry.apiPort)
EXPECTED_WIFI_AUTO_RECOVERY=$(read_default ExoSentry.wifiAutoRecoveryEnabled)
EXPECTED_THUNDERBOLT_ENABLED=$(read_default ExoSentry.thunderboltIPEnabled)
EOF

  echo "Snapshot written: $STATE_FILE"
  echo "Please reboot and login, then run: Scripts/reboot_behavior_validation.sh verify"
}

verify() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "State file missing: $STATE_FILE"
    echo "Run snapshot first: Scripts/reboot_behavior_validation.sh snapshot"
    exit 1
  fi

  source "$STATE_FILE"

  local current_boot_epoch rebooted login_item_registered process_running
  current_boot_epoch="$(collect_boot_epoch)"
  login_item_registered="$(collect_login_item_registered)"
  process_running="$(collect_process_running)"

  if [[ "$current_boot_epoch" -gt "$SNAPSHOT_BOOT_EPOCH" ]]; then
    rebooted="PASS"
  else
    rebooted="FAIL"
  fi

  local mode_now targets_now thermal_now port_now wifi_recovery_now thunderbolt_now
  mode_now="$(read_default ExoSentry.operatingMode)"
  targets_now="$(read_default ExoSentry.targetProcesses)"
  thermal_now="$(read_default ExoSentry.thermalThreshold)"
  port_now="$(read_default ExoSentry.apiPort)"
  wifi_recovery_now="$(read_default ExoSentry.wifiAutoRecoveryEnabled)"
  thunderbolt_now="$(read_default ExoSentry.thunderboltIPEnabled)"

  {
    echo "# ExoSentry 重启后行为验收记录"
    echo
    echo "- 验证时间(UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- 快照时间(UTC): ${SNAPSHOT_AT:-unknown}"
    echo "- 重启检测: $rebooted (snapshot boot=$SNAPSHOT_BOOT_EPOCH, current boot=$current_boot_epoch)"
    echo "- 开机自启注册存在: $login_item_registered (snapshot=${SNAPSHOT_LOGIN_ITEM_REGISTERED:-unknown})"
    echo "- 登录后进程运行: $process_running"
    echo
    echo "## 配置恢复对比"
    echo "- operatingMode: expected='${EXPECTED_OPERATING_MODE:-}' current='$mode_now'"
    echo "- targetProcesses: expected='${EXPECTED_TARGET_PROCESSES:-}' current='$targets_now'"
    echo "- thermalThreshold: expected='${EXPECTED_THERMAL_THRESHOLD:-}' current='$thermal_now'"
    echo "- apiPort: expected='${EXPECTED_API_PORT:-}' current='$port_now'"
    echo "- wifiAutoRecoveryEnabled: expected='${EXPECTED_WIFI_AUTO_RECOVERY:-}' current='$wifi_recovery_now'"
    echo "- thunderboltIPEnabled: expected='${EXPECTED_THUNDERBOLT_ENABLED:-}' current='$thunderbolt_now'"
  } >"$REPORT_FILE"

  local failed=0
  [[ "$rebooted" == "PASS" ]] || failed=1
  [[ "$mode_now" == "${EXPECTED_OPERATING_MODE:-}" ]] || failed=1
  [[ "$targets_now" == "${EXPECTED_TARGET_PROCESSES:-}" ]] || failed=1
  [[ "$thermal_now" == "${EXPECTED_THERMAL_THRESHOLD:-}" ]] || failed=1
  [[ "$port_now" == "${EXPECTED_API_PORT:-}" ]] || failed=1
  [[ "$wifi_recovery_now" == "${EXPECTED_WIFI_AUTO_RECOVERY:-}" ]] || failed=1
  [[ "$thunderbolt_now" == "${EXPECTED_THUNDERBOLT_ENABLED:-}" ]] || failed=1

  echo "Report written: $REPORT_FILE"

  if [[ $failed -ne 0 ]]; then
    echo "Verification FAILED. See report for details."
    exit 1
  fi

  echo "Verification PASSED."
}

case "${1:-}" in
  snapshot)
    snapshot
    ;;
  verify)
    verify
    ;;
  *)
    echo "Usage: Scripts/reboot_behavior_validation.sh <snapshot|verify>"
    exit 1
    ;;
esac
