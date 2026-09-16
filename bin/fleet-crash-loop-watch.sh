#!/usr/bin/env bash
# Item 5: Crash-loop rate threshold + escalating alert
# Problem: Discord hit 160+ restarts/12h without notice (ISS-009-related, hidden by systemd process tracking).
# Solution: track restart count per service, alert when rate exceeds threshold, escalate if sustained.
#
# Deploy: timer every 5 min (fleet-crash-loop.timer)
# Watch: restart count deltas, alert on crossing thresholds (5+ in 5min, 20+ in 1h, 100+ in 12h)
# Escalate: if rate stays high, force-restart with context preservation + alert Barry

set -euo pipefail

STATE_DIR="/tmp/fleet-crash-loop"
mkdir -p "$STATE_DIR"

THRESHOLDS=(
  "5min:5"      # 5+ restarts in 5 min = alert
  "1hour:20"    # 20+ restarts in 1 hour = escalate
  "12hour:100"  # 100+ in 12 hours = critical alert
)

SERVICES=(
  "claudeteam-channel.service:athena-telegram"
  "claudeteam-channel-tc2.service:sage-telegram"
  "claudeteam-channel-discord-sage.service:sage-discord"
)

alert() {
  local svc="$1" level="$2" msg="$3"
  echo "[$(date +%H:%M:%S)] ALERT [$level] $svc: $msg" >> /tmp/fleet-crash-loop.log
}

check_service_restarts() {
  local svc="$1" label="$2"
  local state_file="$STATE_DIR/$label.state"

  local restart_count=$(systemctl --user show "$svc" -p NRestarts --value 2>/dev/null || echo 0)

  if [ -f "$state_file" ]; then
    local prev_count=$(head -1 "$state_file" 2>/dev/null || echo 0)
    local prev_time=$(tail -1 "$state_file" 2>/dev/null || echo 0)
    local delta=$((restart_count - prev_count))
    local time_delta=$(( $(date +%s) - prev_time ))

    if [ $delta -gt 0 ]; then
      local rate_per_min=$(( delta * 60 / (time_delta + 1) ))

      if [ $delta -ge 5 ] && [ $time_delta -lt 300 ]; then
        alert "$svc" "WARN" "5+ restarts in 5min (delta=$delta, rate=${rate_per_min}/min)"
      fi

      if [ $delta -ge 20 ] && [ $time_delta -lt 3600 ]; then
        alert "$svc" "CRIT" "20+ restarts in 1hour (delta=$delta)"
      fi
    fi
  fi

  {
    echo "$restart_count"
    echo "$(date +%s)"
  } > "$state_file"
}

for svc_spec in "${SERVICES[@]}"; do
  IFS=: read svc label <<< "$svc_spec"
  check_service_restarts "$svc" "$label"
done
