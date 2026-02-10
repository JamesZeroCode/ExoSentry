#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/4] Verify release config files exist"
test -f "$ROOT_DIR/Xcode/xcconfigs/Base.xcconfig"
test -f "$ROOT_DIR/Xcode/Entitlements/ExoSentryApp.entitlements"
test -f "$ROOT_DIR/Xcode/InfoPlists/ExoSentryApp-Info.plist"

echo "[2/4] Verify SMJobBless metadata"
grep -q "SMPrivilegedExecutables" "$ROOT_DIR/Xcode/InfoPlists/ExoSentryApp-Info.plist"
grep -q "SMAuthorizedClients" "$ROOT_DIR/Xcode/InfoPlists/ExoSentryHelper-Info.plist"

echo "[3/4] Verify localhost-only status API implementation"
grep -q "403 Forbidden" "$ROOT_DIR/Sources/ExoSentryCore/LocalStatusServer.swift"
grep -q "isLoopback" "$ROOT_DIR/Sources/ExoSentryCore/LocalStatusServer.swift"

echo "[4/4] Run automated tests"
cd "$ROOT_DIR"
swift test

echo "Release hardening check completed."
