#!/usr/bin/env bash
# Helen session watchdog — restarts only on genuine failures, not on a timer.
# Separate from bazment-guardian (which watches bridges) and from the 2h
# claude-helen-reset.timer (which recycles context on schedule).

set -euo pipefail
SERVICE="claude-helen-telegram.service"
LOG="$HOME/claudeclaw/logs/helen-watchdog.log"
WARN_MEM_MB=4096

mkdir -p "$(dirname "$LOG")"
log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') $*" | tee -a "$LOG"; }

# Check service state
STATE=$(systemctl --user show "$SERVICE" --property=ActiveState 2>/dev/null | cut -d= -f2)
SUB=$(systemctl --user show "$SERVICE" --property=SubState 2>/dev/null | cut -d= -f2)
MAIN_PID=$(systemctl --user show "$SERVICE" --property=MainPID 2>/dev/null | grep -oP 'MainPID=\K\d+')

log "Watchdog check: state=$STATE sub=$SUB pid=${MAIN_PID:-none}"

# Condition 1: service not running -> restart
if [[ "$STATE" != "active" || "$SUB" != "running" ]]; then
  log "SERVICE DOWN (state=$STATE/$SUB) — restarting"
  systemctl --user start "$SERVICE"
  log "Restart issued"
  exit 0
fi

# Condition 2: memory check (warn only)
if [[ -n "$MAIN_PID" && "$MAIN_PID" != "0" ]]; then
  MEM_KB=$(cat /proc/$MAIN_PID/status 2>/dev/null | grep VmRSS | awk '{print $2}' || echo 0)
  MEM_MB=$(( MEM_KB / 1024 ))
  if [[ "$MEM_MB" -gt "$WARN_MEM_MB" ]]; then
    log "WARN: high memory usage ${MEM_MB}MB > ${WARN_MEM_MB}MB"
  fi
fi

# Condition 3: JSONL staleness (warn only, never auto-restart).
# Helen's session cwd is ~/claudeclaw, so her transcripts land in
# ~/.claude/projects/-home-apex-claudeclaw. From outside, a quiet-but-healthy
# session is indistinguishable from a hung one; restarting on staleness alone
# would be a timer-restart in disguise. The 2h claude-helen-reset.timer
# already recycles the session, so a stale session self-heals within 2h.
JSONL_DIR="$HOME/.claude/projects/-home-apex-claudeclaw"
FRESH=$(find "$JSONL_DIR" -maxdepth 1 -name '*.jsonl' -newermt '-30 minutes' 2>/dev/null | head -1)
if [[ -z "$FRESH" ]]; then
  log "WARN: no JSONL activity in 30+ min (idle or possibly unresponsive) — not restarting; 2h reset timer covers recovery"
fi

log "Service healthy"
