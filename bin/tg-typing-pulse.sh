#!/usr/bin/env bash
# Keep the Telegram "typing…" bubble alive while Claude works.
#
# Telegram's sendChatAction shows "typing…" for only ~5s and is not repeated.
# The channel plugin fires it once per inbound message, so for any task that
# runs longer than 5s the bubble disappears before we reply. This script is
# wired into the PostToolUse hook: every tool call re-pulses "typing", so the
# bubble stays lit the whole time we're working and naturally clears ~5s after
# the last tool runs (i.e. right as we send the reply).
#
# Fully fire-and-forget: never blocks, never errors out a tool call.
set +e
# Node-aware: each fleet node exports TELEGRAM_STATE_DIR (e.g. ~/apex/agents/sage/telegram) in its
# run-channel-service-*.sh, and hooks inherit it. Pulse the bot THIS node actually
# talks through — not the generic telegram/ dir, which is a different bot id Barry
# never sees on this node. Falls back to the default dir for legacy single-bot nodes.
STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/apex/agents/athena/telegram}"
ENV_FILE="$STATE_DIR/.env"
CHAT_ID="6062064959"   # Barry's DM chat

[ -r "$ENV_FILE" ] || exit 0
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || exit 0

curl -s --max-time 3 \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendChatAction" \
  -d chat_id="$CHAT_ID" -d action=typing >/dev/null 2>&1 || true
exit 0
