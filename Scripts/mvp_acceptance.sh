#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/7] Swift tests"
cd "$ROOT_DIR"
swift test

echo "[2/7] Plist and entitlements lint"
plutil -lint \
  "$ROOT_DIR/Xcode/InfoPlists/ExoSentryApp-Info.plist" \
  "$ROOT_DIR/Xcode/InfoPlists/ExoSentryCore-Info.plist" \
  "$ROOT_DIR/Xcode/InfoPlists/ExoSentryXPC-Info.plist" \
  "$ROOT_DIR/Xcode/InfoPlists/ExoSentryHelper-Info.plist" \
  "$ROOT_DIR/Xcode/Entitlements/ExoSentryApp.entitlements" \
  "$ROOT_DIR/Xcode/Entitlements/ExoSentryXPC.entitlements" \
  "$ROOT_DIR/Xcode/Entitlements/ExoSentryHelper.entitlements" \
  "$ROOT_DIR/Xcode/LaunchDaemons/com.exosentry.helper.plist"

echo "[3/7] F-01 Manual: power assertion"
echo "- Launch app and enable guard mode."
echo "- Verify system stays awake without input for >10 min."

echo "[4/7] F-02 Manual: clamshell + rollback"
echo "- Enable cluster mode, close lid, verify SSH remains connected."
echo "- Disable guard and run: pmset -g | grep disablesleep (expect 0)."

echo "[5/7] F-05/F-07 Manual: process linkage + status API"
echo "- Start target process, verify status becomes active."
echo "- Stop target process, verify status becomes paused."
echo "- Run: curl -s http://127.0.0.1:1988/status"

echo "[6/7] F-06 Manual: network recovery"
echo "- Simulate gateway/offline state and wait for retry window."
echo "- Verify helper attempts Wi-Fi restart and network_state recovers from offline/lan_lost."

echo "[7/7] F-08 + XPC stability: thermal trip + permission recovery"
echo "- Simulate high temp path and verify status overheat_trip then manual recover."
echo "- Simulate privilege loss and use one-click repair; verify status returns healthy."
echo "- Restart app and machine, then verify privileged operations no longer intermittently fail."

echo "MVP acceptance checklist completed."
