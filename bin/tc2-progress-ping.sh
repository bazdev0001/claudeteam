#!/usr/bin/env bash
# Hermes-style progress ping (Barry, 2026-07-04): while I'm actively working on an
# unanswered request for >5 min, tell him every 5 min that I'm still on it.
# Runs every minute via tc2-progress-ping.timer.
#
# Stamps (touched by hooks in ~/.claude/settings.json):
#   tc2-last-inbound — UserPromptSubmit (a message entered the session)
#   tc2-last-reply   — PostToolUse on the telegram reply tool
# Conditions to ping: inbound newer than last reply, >=5 min old, session JSONL
# active in the last 3 min (working, not frozen), last ping >=5 min ago.

set -uo pipefail
CACHE="$HOME/.cache"
IN="$CACHE/tc2-last-inbound"
OUT="$CACHE/tc2-last-reply"
PING="$CACHE/tc2-last-ping"
JSONL_DIR="$HOME/.claude/projects/-home-barry-projects-claudeteam"
ENV_FILE="$HOME/apex/agents/sage/telegram/.env"
CHAT_ID="6062064959"

[ -f "$IN" ] || exit 0
now=$(date +%s)
in_t=$(stat -c %Y "$IN")
out_t=$(stat -c %Y "$OUT" 2>/dev/null || echo 0)
ping_t=$(stat -c %Y "$PING" 2>/dev/null || echo 0)

(( in_t > out_t )) || exit 0                    # already answered
(( now - in_t >= 300 )) || exit 0               # give normal replies 5 min
(( now - ping_t >= 300 )) || exit 0             # throttle pings to 5 min

newest_jsonl=$(find "$JSONL_DIR" -maxdepth 1 -name '*.jsonl' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
[ -n "${newest_jsonl:-}" ] || exit 0
(( now - newest_jsonl <= 180 )) || exit 0       # not actively working -> frozen tooling handles it

# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || exit 0

mins=$(( (now - in_t) / 60 ))
curl -s --max-time 5 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode "text=⏳ Still on it (${mins} min in) — working through your request, will report when done." >/dev/null 2>&1 || true
touch "$PING"
