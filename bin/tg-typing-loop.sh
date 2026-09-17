#!/usr/bin/env bash
# tg-typing-loop.sh — Keep Telegram "typing..." alive while a background agent works.
#
# Usage: bash tg-typing-loop.sh [duration_seconds]
#
# Pulses sendChatAction every 4s for up to $DURATION seconds (default 300 = 5 min).
# Stops early if a sentinel file disappears: touch /tmp/tc2-typing-active to start,
# rm it to stop.
#
# Run in background when spawning a sub-agent:
#   touch /tmp/tc2-typing-active
#   bash bin/tg-typing-loop.sh 300 &

set +e
DURATION="${1:-300}"
SENTINEL="/tmp/tc2-typing-active"
PULSE="$(dirname "$0")/tg-typing-pulse.sh"

END=$(( $(date +%s) + DURATION ))

while [ "$(date +%s)" -lt "$END" ]; do
    [ -f "$SENTINEL" ] || break
    bash "$PULSE" 2>/dev/null || true
    sleep 4
done
