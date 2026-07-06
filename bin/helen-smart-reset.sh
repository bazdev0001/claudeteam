#!/usr/bin/env bash
# Smart reset for Helen's Claude Code session.
# - Checks if Claude is actively processing before restarting
# - Defers up to 5 times (5 min total) if busy
# - Saves context to Obsidian before restart
# - Clears stale inbox files

set -euo pipefail

INBOX_DIR="$HOME/.claude/channels/telegram-helen/inbox"
MAX_RETRIES=5
RETRY_DELAY=60  # seconds between retries when busy
LOG="$HOME/claudeclaw/logs/helen-smart-reset.log"

mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') $*" | tee -a "$LOG"; }

is_claude_busy() {
  # Get CPU% of the claude process
  local pid
  pid=$(pgrep -f "claude --dangerously-skip-permissions.*telegram-helen" 2>/dev/null | head -1) || true
  [[ -z "$pid" ]] && return 1  # not running = not busy

  local cpu
  cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' | cut -d. -f1) || return 1
  [[ -n "$cpu" && "$cpu" -gt 3 ]]
}

log "Smart reset triggered"

# Check if busy, retry up to MAX_RETRIES times
retries=0
while is_claude_busy; do
  retries=$((retries + 1))
  if [[ $retries -ge $MAX_RETRIES ]]; then
    log "Still busy after $MAX_RETRIES retries — proceeding with reset anyway"
    break
  fi
  log "Claude is processing (CPU active) — deferring reset, retry $retries/$MAX_RETRIES in ${RETRY_DELAY}s"
  sleep "$RETRY_DELAY"
done

# Save context to Obsidian before kill
log "Saving context to Obsidian journal..."
bash "$HOME/bin/helen-save-context.sh" >> "$LOG" 2>&1 || log "WARN: context save failed (non-fatal)"

# Clear inbox files older than 30 minutes (not 2h — new shorter cycle)
find "$INBOX_DIR" -name "*.oga" -mmin +30 -delete 2>/dev/null || true

# Restart the service
log "Restarting claude-helen-telegram.service..."
systemctl --user restart claude-helen-telegram.service
log "Restart issued. Done."
