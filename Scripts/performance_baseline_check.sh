#!/usr/bin/env bash
set -euo pipefail

PROCESS_NAME="${1:-ExoSentryApp}"
SAMPLE_COUNT="${EXOSENTRY_SAMPLE_COUNT:-5}"
SAMPLE_INTERVAL_SECONDS="${EXOSENTRY_SAMPLE_INTERVAL_SECONDS:-1}"
CPU_THRESHOLD="${EXOSENTRY_CPU_THRESHOLD:-0.5}"
MEMORY_THRESHOLD_MB="${EXOSENTRY_MEMORY_THRESHOLD_MB:-50}"

if ! [[ "$SAMPLE_COUNT" =~ ^[0-9]+$ ]] || [ "$SAMPLE_COUNT" -le 0 ]; then
  echo "Invalid EXOSENTRY_SAMPLE_COUNT: $SAMPLE_COUNT"
  exit 2
fi

if ! [[ "$SAMPLE_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [ "$SAMPLE_INTERVAL_SECONDS" -lt 1 ]; then
  echo "Invalid EXOSENTRY_SAMPLE_INTERVAL_SECONDS: $SAMPLE_INTERVAL_SECONDS"
  exit 2
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

for _ in $(seq 1 "$SAMPLE_COUNT"); do
  ps -A -o comm=,%cpu=,rss= >> "$TMP_FILE"
  sleep "$SAMPLE_INTERVAL_SECONDS"
done

python3 - "$TMP_FILE" "$PROCESS_NAME" "$CPU_THRESHOLD" "$MEMORY_THRESHOLD_MB" <<'PY'
import pathlib
import statistics
import sys

path = pathlib.Path(sys.argv[1])
process_name = sys.argv[2]
cpu_threshold = float(sys.argv[3])
memory_threshold_mb = float(sys.argv[4])

cpu_values = []
rss_values_kb = []

for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
    parts = raw.split()
    if len(parts) < 3:
        continue
    command = pathlib.Path(parts[0]).name
    if command != process_name:
        continue

    try:
        cpu_values.append(float(parts[1]))
        rss_values_kb.append(float(parts[2]))
    except ValueError:
        continue

if not cpu_values or not rss_values_kb:
    print(f"No running process matched '{process_name}'.")
    sys.exit(2)

avg_cpu = statistics.fmean(cpu_values)
max_memory_mb = max(rss_values_kb) / 1024.0

print(f"Process: {process_name}")
print(f"Avg CPU: {avg_cpu:.3f}% (threshold <= {cpu_threshold:.3f}%)")
print(f"Max Memory: {max_memory_mb:.2f} MB (threshold <= {memory_threshold_mb:.2f} MB)")

exceeded = False
if avg_cpu > cpu_threshold:
    print("ALERT: CPU threshold exceeded")
    exceeded = True
if max_memory_mb > memory_threshold_mb:
    print("ALERT: Memory threshold exceeded")
    exceeded = True

if exceeded:
    sys.exit(1)

print("PASS: Resource usage is within thresholds")
PY
