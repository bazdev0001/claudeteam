#!/usr/bin/env bash
# Detached background worker for Helen's 30-second responsiveness rule (Barry, 2026-07-05).
# Runs a headless claude task fully detached from the bridge's per-message process
# (which exits after each reply — in-process background agents would be killed),
# then sends the result straight to Barry on Telegram.
# Usage: helen-bg.sh "<self-contained task prompt>" ["short label"]
set -uo pipefail
TASK="${1:?usage: helen-bg.sh \"task\" [label]}"
LABEL="${2:-background task}"
ENV_FILE="$HOME/.claude/channels/telegram-helen/.env"
TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
CHAT_ID="6062064959"
STATE_DIR="$HOME/helen-bridge/state"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/bg-$(date +%s)-$$.log"

export TASK LABEL TOKEN CHAT_ID LOG
setsid nohup bash -c '
  OUT=$(cd "$HOME/helen-home" && claude -p "$TASK" --model claude-fable-5 \
        --dangerously-skip-permissions \
        --append-system-prompt "$(cat "$HOME/.claude/helen-soul.md")" 2>>"$LOG")
  printf "%s\n" "$OUT" >>"$LOG"
  if [ -n "$OUT" ]; then
    MSG="✅ ${LABEL} — done:
${OUT:0:3500}"
  else
    MSG="⚠️ ${LABEL} — finished with no output; see $LOG"
  fi
  curl -s --max-time 15 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" --data-urlencode "text=$MSG" >/dev/null
' >>"$LOG" 2>&1 &
echo "launched: $LABEL -> $LOG"
