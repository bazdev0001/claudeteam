#!/usr/bin/env bash
# Item 6: Capability manifest assertion check
# Problem: capability declarations go stale; missing capability = silent fallback.
# This hid the three dead scripts (they tried to use missing Telegram token).
#
# Solution: compare declared capabilities (manifest.txt) vs actual availability.
# Alert: any capability declared but unavailable = FAIL + alert Barry.
#
# Deploy: timer daily at 02:00 (fleet-capability-check.timer)

set -euo pipefail

MANIFEST="/home/barry/projects/claudeteam/bin/monitor-manifest.txt"
FAIL_LOG="/tmp/fleet-capability-failures.log"
> "$FAIL_LOG"

check_capability() {
  local cap="$1" type="${2:-mcp}" detail="${3:-}"

  case "$type" in
    mcp)
      if ! command -v "$detail" &>/dev/null 2>&1; then
        echo "[$(date +%H:%M:%S)] FAIL: MCP $cap (expected: $detail)" | tee -a "$FAIL_LOG"
        return 1
      fi
      ;;
    env)
      if ! systemctl --user show -p Environment "$detail" 2>/dev/null | grep -q "$cap"; then
        echo "[$(date +%H:%M:%S)] FAIL: ENV $cap not found in $detail" | tee -a "$FAIL_LOG"
        return 1
      fi
      ;;
    tool)
      if ! command -v "$cap" &>/dev/null; then
        echo "[$(date +%H:%M:%S)] FAIL: TOOL $cap not found" | tee -a "$FAIL_LOG"
        return 1
      fi
      ;;
    file)
      if [ ! -f "$cap" ]; then
        echo "[$(date +%H:%M:%S)] FAIL: FILE $cap missing" | tee -a "$FAIL_LOG"
        return 1
      fi
      ;;
  esac

  echo "[$(date +%H:%M:%S)] OK: $cap ($type)"
  return 0
}

while read -r line; do
  [ -n "$line" ] || continue
  cap=$(echo "$line" | cut -d: -f2 | xargs)
  type=$(echo "$line" | cut -d: -f3 | xargs)
  detail=$(echo "$line" | cut -d: -f4- | xargs)
  check_capability "$cap" "$type" "$detail" || true
done < <(grep "^capability:" "$MANIFEST" 2>/dev/null || true)

for tool in curl jq bash systemctl; do
  check_capability "$tool" "tool" || true
done

check_capability "/home/barry/projects/claudeteam/rules.md" "file" || true
check_capability "/home/barry/projects/obsidian/00-Briefing.md" "file" || true

if [ -s "$FAIL_LOG" ]; then
  echo "Capability check FAILED — see $FAIL_LOG"
  exit 1
fi

echo "All capabilities verified OK"
