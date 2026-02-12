#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_PROTO="$ROOT_DIR/Sources/ExoSentryHelper/HelperXPCProtocol.swift"
XPC_PROTO="$ROOT_DIR/Sources/ExoSentryXPC/HelperXPCProtocol.swift"

extract_protocol_block() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import pathlib
import sys

file_path = pathlib.Path(sys.argv[1])
text = file_path.read_text(encoding="utf-8")
start = text.find("@objc public protocol ExoSentryHelperXPCProtocol")
if start < 0:
    raise SystemExit(2)
brace = text.find("{", start)
if brace < 0:
    raise SystemExit(3)

depth = 0
end = -1
for idx in range(brace, len(text)):
    ch = text[idx]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = idx
            break

if end < 0:
    raise SystemExit(4)

block = text[start:end + 1]
print(block.strip())
PY
}

helper_block="$(extract_protocol_block "$HELPER_PROTO")"
xpc_block="$(extract_protocol_block "$XPC_PROTO")"

if [[ "$helper_block" != "$xpc_block" ]]; then
  echo "XPC protocol declarations are out of sync:"
  echo "- $HELPER_PROTO"
  echo "- $XPC_PROTO"
  echo "Please keep ExoSentryHelperXPCProtocol signatures mirrored."
  exit 1
fi

echo "XPC protocol sync check passed."
