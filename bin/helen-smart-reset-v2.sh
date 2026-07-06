#!/usr/bin/env bash
# Smart reset v2 for Helen Telegram session.
# Two independent reset conditions:
#   1. Clean reset: idle 15+ min AND session 6+ hours old
#   2. Context reset: JSONL > 1.5MB AND not mid-processing (may interrupt active session)
# Never resets on a fixed timer.

set -euo pipefail

SERVICE="claude-helen-telegram.service"
IDLE_MINUTES=15          # must be idle this long before any reset
SESSION_AGE_HOURS=6      # reset after 6h if idle
CONTEXT_BYTES=$((1500 * 1024))  # 1.5MB = context pressure threshold (reset regardless of age if idle)
LOG="$HOME/claudeclaw/logs/helen-smart-reset.log"
JOURNAL="$HOME/bazment/obsidian/journal/$(date +%Y-%m-%d).md"

mkdir -p "$(dirname "$LOG")"
log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') $*" | tee -a "$LOG"; }

# Get the helen session PID from systemd
get_pid() {
  systemctl --user show "$SERVICE" --property=MainPID 2>/dev/null \
    | grep -oP 'MainPID=\K\d+' || echo ""
}

# Find the active session JSONL for the helen process.
# Claude writes and closes the JSONL each turn (not kept open), so lsof won't find it.
# Instead: find the claude child of the service, get its cwd, derive the project dir,
# then return the most recently modified JSONL there.
get_session_jsonl() {
  local main_pid="$1"
  [[ -z "$main_pid" || "$main_pid" == "0" ]] && return

  # Walk children to find the actual claude binary process
  local claude_pid
  claude_pid=$(pgrep -P "$main_pid" -a 2>/dev/null | while read p cmd; do
    echo "$p $cmd"
    pgrep -P "$p" -a 2>/dev/null
  done | grep -oP '^\d+(?=.*\bclaude\b)' | head -1)

  # Fall back to any claude process that is a descendant
  [[ -z "$claude_pid" ]] && \
    claude_pid=$(ps --ppid "$main_pid" -o pid= 2>/dev/null | head -1)
  [[ -z "$claude_pid" ]] && return

  # Get cwd of the claude process
  local cwd
  cwd=$(readlink -f "/proc/$claude_pid/cwd" 2>/dev/null) || return
  # Derive project key: replace / with - and strip leading -
  local proj_key
  proj_key=$(echo "$cwd" | sed 's|/|-|g')
  local proj_dir="$HOME/.claude/projects/$proj_key"
  [[ -d "$proj_dir" ]] || return

  # Return the most recently modified JSONL in that project dir
  find "$proj_dir" -maxdepth 1 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | awk '{print $2}'
}

# Check if Claude is actively processing (CPU > 3%)
is_busy() {
  local pid="$1"
  [[ -z "$pid" || "$pid" == "0" ]] && return 1
  local cpu
  cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' | cut -d. -f1) || return 1
  [[ -n "$cpu" && "$cpu" -gt 3 ]]
}

# Minutes since a file was last modified
minutes_since_mtime() {
  local f="$1"
  [[ -f "$f" ]] || { echo 9999; return; }
  echo $(( ( $(date +%s) - $(stat -c %Y "$f") ) / 60 ))
}

PID=$(get_pid)
JSONL=$(get_session_jsonl "$PID")

log "--- Check run (PID=${PID:-none}, JSONL=${JSONL:-none})"

if [[ -z "$PID" || "$PID" == "0" ]]; then
  log "Service not running — nothing to do"
  exit 0
fi

# Determine idle time from JSONL mtime (updated every turn)
IDLE_MINS=0
JSONL_SIZE=0
if [[ -n "$JSONL" && -f "$JSONL" ]]; then
  IDLE_MINS=$(minutes_since_mtime "$JSONL")
  JSONL_SIZE=$(stat -c %s "$JSONL" 2>/dev/null || echo 0)
  log "Session JSONL: $JSONL | size=${JSONL_SIZE}B | idle=${IDLE_MINS}min"
else
  log "WARN: could not find session JSONL — using service uptime as idle proxy"
  ACTIVE_SECS=$(systemctl --user show "$SERVICE" --property=ActiveEnterTimestamp 2>/dev/null \
    | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' \
    | xargs -I{} date -d "{} UTC" +%s 2>/dev/null || echo 0)
  [[ "$ACTIVE_SECS" -gt 0 ]] && IDLE_MINS=$(( ( $(date +%s) - ACTIVE_SECS ) / 60 ))
fi

# Session age in minutes
SESSION_START=$(systemctl --user show "$SERVICE" --property=ActiveEnterTimestamp 2>/dev/null \
  | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' \
  | xargs -I{} date -d "{} UTC" +%s 2>/dev/null || echo 0)
SESSION_AGE_MINS=0
[[ "$SESSION_START" -gt 0 ]] && SESSION_AGE_MINS=$(( ( $(date +%s) - SESSION_START ) / 60 ))
SESSION_AGE_THRESHOLD_MINS=$(( SESSION_AGE_HOURS * 60 ))

log "Session age: ${SESSION_AGE_MINS}min (threshold ${SESSION_AGE_THRESHOLD_MINS}min)"

# Check conditions
SHOULD_RESET=0
REASON=""
IS_BUSY_NOW=$(is_busy "$PID" && echo 1 || echo 0)

# Condition 1: clean reset — idle 15+ min AND session 6+ hours old
if [[ "$IDLE_MINS" -ge "$IDLE_MINUTES" && "$IS_BUSY_NOW" -eq 0 \
      && "$SESSION_AGE_MINS" -ge "$SESSION_AGE_THRESHOLD_MINS" ]]; then
  SHOULD_RESET=1
  REASON="clean reset: idle ${IDLE_MINS}min, session age ${SESSION_AGE_MINS}min"
fi

# Condition 2: context heavy — fires independently of idle/age, only requires not mid-processing
if [[ "$JSONL_SIZE" -ge "$CONTEXT_BYTES" && "$IS_BUSY_NOW" -eq 0 ]]; then
  SHOULD_RESET=1
  REASON="context heavy: ${JSONL_SIZE}B >= ${CONTEXT_BYTES}B (session ${SESSION_AGE_MINS}min old)"
fi

if [[ "$SHOULD_RESET" -eq 0 ]]; then
  log "No reset needed (idle=${IDLE_MINS}min, size=${JSONL_SIZE}B, busy=$(is_busy "$PID" && echo yes || echo no))"
  exit 0
fi

log "Reset condition met: $REASON"

# Save context note to Obsidian
{
  echo ""
  echo "### $(date -u '+%H:%M') UTC — [Helen Reset] $REASON"
  echo "- Session age: ${IDLE_MINS}min idle, JSONL ${JSONL_SIZE}B"
  echo "- Restarting claude-helen-telegram.service"
} >> "$JOURNAL" 2>/dev/null || log "WARN: Obsidian journal write failed"

# Save context before restart
log "Saving context and uploading to vault..."
bash "$HOME/bin/helen-save-context.sh" >> "$LOG" 2>&1 || log "WARN: save-context failed"

# Restart
log "Restarting $SERVICE..."
systemctl --user restart "$SERVICE"
log "Restart issued. Done."
