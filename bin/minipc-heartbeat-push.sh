#!/usr/bin/env bash
# minipc-heartbeat-push.sh — push a heartbeat timestamp from the mini-PC to the VPS.
# Runs every 5 min via minipc-heartbeat-push.timer (mini-PC, WSL).
# The VPS side (barry@vps ~/bin/minipc-heartbeat-check.sh) alerts Barry if this
# file goes stale >15 min — the ONLY external signal that the mini-PC/WSL is alive.

set -uo pipefail
VPS="barry@srv1601002.hstgr.cloud"
LOG="$HOME/logs/minipc-heartbeat-push.log"

if ssh -o BatchMode=yes -o ConnectTimeout=15 "$VPS" \
    'date -u +%s > /home/barry/.minipc-heartbeat' 2>/dev/null; then
  exit 0  # healthy — no log spam
fi

echo "$(date '+%F %T') push FAILED (VPS unreachable?)" >> "$LOG"
tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
exit 1
