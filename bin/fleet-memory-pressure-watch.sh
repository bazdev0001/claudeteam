#!/usr/bin/env bash
# Item 8: Memory-pressure check — Athena's process already ~2GB
# Problem: memory leaks in long-running sessions (Athena's trading node, 24/7).
# No alert when process grows unbounded.
#
# Solution: monitor RSS/VSZ per service, alert at thresholds.
# Deploy: timer every 15 min (fleet-memory-watch.timer)
# Alert: warn at 2GB, critical at 2.5GB

set -euo pipefail

MEMORY_LOG="/tmp/fleet-memory-watch.log"
WARN_MB=2048
CRIT_MB=2560

log_memory() {
  local label="$1" pid="$2" rss_mb="$3" vsz_mb="$4" level="${5:-info}"
  {
    echo "[$(date +%H:%M:%S)] [$level] $label pid=$pid RSS=${rss_mb}MB VSZ=${vsz_mb}MB"
  } >> "$MEMORY_LOG"
}

check_process_memory() {
  local label="$1" svc="$2"

  local pid=$(systemctl --user show -p MainPID "$svc" --value 2>/dev/null)
  [ -z "$pid" ] || [ "$pid" == "0" ] && return 0

  if [ -r "/proc/$pid/status" ]; then
    local rss_kb=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status")
    local vsz_kb=$(awk '/^VmPeak:/{print $2}' "/proc/$pid/status")

    [ -z "$rss_kb" ] && return 0

    local rss_mb=$((rss_kb / 1024))
    local vsz_mb=$((vsz_kb / 1024))

    if [ $rss_mb -ge $CRIT_MB ]; then
      log_memory "$label" "$pid" "$rss_mb" "$vsz_mb" "CRIT"
      return 1
    elif [ $rss_mb -ge $WARN_MB ]; then
      log_memory "$label" "$pid" "$rss_mb" "$vsz_mb" "WARN"
    else
      log_memory "$label" "$pid" "$rss_mb" "$vsz_mb" "info"
    fi
  fi
  return 0
}

check_process_memory "Athena-telegram" "claudeteam-channel.service" || true
check_process_memory "Sage-telegram" "claudeteam-channel-tc2.service" || true
check_process_memory "Sage-discord" "claudeteam-channel-discord-sage.service" || true

echo "Memory check complete (see $MEMORY_LOG)"
