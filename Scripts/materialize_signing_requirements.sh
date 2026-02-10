#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PLIST="$ROOT_DIR/Xcode/InfoPlists/ExoSentryApp-Info.plist"
HELPER_PLIST="$ROOT_DIR/Xcode/InfoPlists/ExoSentryHelper-Info.plist"
BASE_XCCONFIG="$ROOT_DIR/Xcode/xcconfigs/Base.xcconfig"
HELPER_BLESSED_INFO="$ROOT_DIR/Xcode/BlessedHelper/com.exosentry.helper-Info.plist"
export APP_PLIST HELPER_PLIST BASE_XCCONFIG HELPER_BLESSED_INFO

if [[ -z "${EXOSENTRY_TEAM_ID:-}" ]]; then
  echo "EXOSENTRY_TEAM_ID is required to avoid writing wrong team."
  echo "Example: export EXOSENTRY_TEAM_ID=F29W647U33"
  exit 1
fi

APP_REQ="identifier \"com.exosentry.app\" and anchor apple generic and certificate leaf[subject.OU] = \"${EXOSENTRY_TEAM_ID}\""
HELPER_REQ="identifier \"com.exosentry.helper\" and anchor apple generic and certificate leaf[subject.OU] = \"${EXOSENTRY_TEAM_ID}\""

python3 - <<'PY'
import plistlib
from pathlib import Path
import os

app_plist = Path(os.environ["APP_PLIST"])
helper_plist = Path(os.environ["HELPER_PLIST"])
helper_blessed_info = Path(os.environ["HELPER_BLESSED_INFO"])
team = os.environ["EXOSENTRY_TEAM_ID"]

app_req = f'identifier "com.exosentry.app" and anchor apple generic and certificate leaf[subject.OU] = "{team}"'
helper_req = f'identifier "com.exosentry.helper" and anchor apple generic and certificate leaf[subject.OU] = "{team}"'

with app_plist.open("rb") as f:
    app = plistlib.load(f)
app.setdefault("SMPrivilegedExecutables", {})["com.exosentry.helper"] = helper_req
with app_plist.open("wb") as f:
    plistlib.dump(app, f)

for p in (helper_plist, helper_blessed_info):
    with p.open("rb") as f:
        data = plistlib.load(f)
    data["SMAuthorizedClients"] = [app_req]
    with p.open("wb") as f:
        plistlib.dump(data, f)
PY

if grep -q '^DEVELOPMENT_TEAM =' "$BASE_XCCONFIG"; then
  perl -0777 -i -pe "s/^DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = ${EXOSENTRY_TEAM_ID}/m" "$BASE_XCCONFIG"
else
  printf "\nDEVELOPMENT_TEAM = %s\n" "$EXOSENTRY_TEAM_ID" >> "$BASE_XCCONFIG"
fi

echo "Materialized signing requirements with Team ID: ${EXOSENTRY_TEAM_ID}"
