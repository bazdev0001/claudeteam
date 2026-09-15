#!/usr/bin/env bash
# tg-auto-ack.sh — UserPromptSubmit hook: instant ack for Telegram messages.
#
# The Telegram plugin already sends the 👀 react automatically (via ackReaction in
# access.json). This hook adds a TEXT ack so Barry sees a message immediately,
# enforcing the zero-second rule in code rather than relying on Claude to remember.
#
# How it works:
#   1. Reads UserPromptSubmit JSON from stdin (field: user_prompt).
#   2. Parses the <channel source="telegram" ...> tag to extract chat_id, message_id,
#      and attachment_file_id (presence = voice message).
#   3. Calls Telegram Bot API directly (curl) to send the ack text.
#   4. Exits 0 — never blocks Claude's response.
#
# The hook is fire-and-forget: all errors are silently swallowed.

set -euo pipefail

# --- read stdin ---
INPUT=$(cat 2>/dev/null) || INPUT=''
[ -z "$INPUT" ] && exit 0

# --- extract user_prompt from UserPromptSubmit JSON ---
PROMPT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('user_prompt', ''))
except Exception:
    pass
" 2>/dev/null) || PROMPT=''

[ -z "$PROMPT" ] && exit 0

# --- check for telegram channel tag ---
# Tag format: <channel source="telegram" chat_id="..." message_id="..." ...>
echo "$PROMPT" | grep -q 'source="telegram"' || exit 0

# --- parse chat_id, message_id, attachment_file_id ---
CHAT_ID=$(echo "$PROMPT" | grep -oP 'chat_id="\K[^"]+' | head -1)
MESSAGE_ID=$(echo "$PROMPT" | grep -oP 'message_id="\K[^"]+' | head -1)
HAS_ATTACHMENT=$(echo "$PROMPT" | grep -c 'attachment_file_id=' || true)

[ -z "$CHAT_ID" ] && exit 0

# --- find bot token ---
# 1) The service unit's own Environment= (authoritative, per-node, always present for a
#    session started by systemd — hooks inherit it). Checked FIRST because the .env files
#    this script originally relied on do not exist on the mini-PC: verified 2026-09-15,
#    no `.env` anywhere under ~/apex/agents/*/telegram/, so every lookup below fell through
#    and this hook exited 0 silently — Barry got the plugin's 👀 reaction but never the
#    text ack. Same silent-death class as ISS-003/006.
# 2) Then TELEGRAM_STATE_DIR/.env, then iterate known dirs (kept for other hosts).
TOKEN="${TELEGRAM_BOT_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -n "${TELEGRAM_STATE_DIR:-}" ] && [ -f "$TELEGRAM_STATE_DIR/.env" ]; then
    TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$TELEGRAM_STATE_DIR/.env" 2>/dev/null | cut -d= -f2-)
fi
if [ -z "$TOKEN" ]; then
    for dir in "$HOME"/apex/agents/*/telegram; do
        [ -f "$dir/.env" ] || continue
        T=$(grep "^TELEGRAM_BOT_TOKEN=" "$dir/.env" 2>/dev/null | cut -d= -f2-)
        if [ -n "$T" ]; then
            TOKEN="$T"
            break
        fi
    done
fi
[ -z "$TOKEN" ] && exit 0

# --- choose ack text ---
if [ "${HAS_ATTACHMENT:-0}" -gt 0 ]; then
    ACK_TEXT="Your voice message: received, transcribing... I am here for your next request Sir :)"
else
    ACK_TEXT="Got it — processing now. I am here for your next request Sir :)"
fi

# --- send ack text (reply to the inbound message if we have message_id) ---
if [ -n "$MESSAGE_ID" ]; then
    curl -s --max-time 5 \
        "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${ACK_TEXT}" \
        -d "reply_to_message_id=${MESSAGE_ID}" \
        >/dev/null 2>&1 || true
else
    curl -s --max-time 5 \
        "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${ACK_TEXT}" \
        >/dev/null 2>&1 || true
fi

exit 0
