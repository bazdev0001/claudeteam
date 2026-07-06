#!/usr/bin/env bash
# Hermes-style progress ping for Helen (rolled out from Sage's tc2 version, Barry 2026-07-04):
# while her session is >5 min into an unanswered request and actively working, tell Barry
# every 5 min that she's still on it. Runs every minute via helen-progress-ping.timer.
#
# Stamps are touched by hooks in ~/.claude/settings.json, scoped per node via
# TELEGRAM_STATE_DIR so Ada's/Sophia's sessions don't pollute Helen's stamps.

set -uo pipefail
CACHE="$HOME/.cache"
IN="$CACHE/inbound-telegram-helen"
OUT="$CACHE/reply-telegram-helen"
PING="$CACHE/ping-telegram-helen"
JSONL_DIR="$HOME/.claude/projects/-home-apex-claudeclaw"
ENV_FILE="$HOME/.claude/channels/telegram-helen/.env"
CHAT_ID="6062064959"

[ -f "$IN" ] || exit 0
now=$(date +%s)
in_t=$(stat -c %Y "$IN")
out_t=$(stat -c %Y "$OUT" 2>/dev/null || echo 0)
ping_t=$(stat -c %Y "$PING" 2>/dev/null || echo 0)

(( in_t > out_t )) || exit 0
(( now - in_t >= 300 )) || exit 0
(( now - ping_t >= 300 )) || exit 0

newest_jsonl=$(find "$JSONL_DIR" -maxdepth 1 -name '*.jsonl' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
[ -n "${newest_jsonl:-}" ] || exit 0
(( now - newest_jsonl <= 180 )) || exit 0

TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
[ -n "$TOKEN" ] || exit 0

mins=$(( (now - in_t) / 60 ))
curl -s --max-time 5 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode "text=⏳ Still on it (${mins} min in) — working through your request, will report when done." >/dev/null 2>&1 || true
touch "$PING"
