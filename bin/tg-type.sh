#!/usr/bin/env bash
# Send Telegram typing action for the active chat.
# Reads TELEGRAM_STATE_DIR to find the bot token.
# Usage: tg-type.sh [chat_id]   (defaults to Barry's hardcoded ID)
CHAT_ID="${1:-6062064959}"
[ -z "$CHAT_ID" ] && exit 0

# Find token from TELEGRAM_STATE_DIR env var (set by channel exec scripts)
if [ -n "$TELEGRAM_STATE_DIR" ] && [ -f "$TELEGRAM_STATE_DIR/.env" ]; then
    TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$TELEGRAM_STATE_DIR/.env" | cut -d= -f2-)
else
    # Fallback: search all known telegram agent dirs for any token
    for dir in "$HOME"/apex/agents/*/telegram; do
        [ -f "$dir/.env" ] || continue
        TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$dir/.env" 2>/dev/null | cut -d= -f2-)
        [ -n "$TOKEN" ] && break
    done
fi

[ -z "$TOKEN" ] && exit 0
curl -sf --max-time 3 "https://api.telegram.org/bot$TOKEN/sendChatAction" \
    -d "chat_id=$CHAT_ID&action=typing" >/dev/null 2>&1 &
