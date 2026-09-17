#!/usr/bin/env bash
# tg-auto-voice.sh — PostToolUse hook: auto-attach TTS voice to every Telegram reply.
# Barry prefers listening. This hook fires after mcp__plugin_telegram_telegram__reply
# and sends the reply text as a voice note without requiring the model to call tg-say.sh.
# Fire-and-forget: all errors swallowed so Claude Code is never blocked.

set -euo pipefail

INPUT=$(cat 2>/dev/null) || INPUT=''
[ -z "$INPUT" ] && exit 0

# Extract text and chat_id from tool_input
CHAT_ID=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    print(ti.get('chat_id', ''))
except Exception:
    pass
" 2>/dev/null) || CHAT_ID=''

TEXT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    print(ti.get('text', ''))
except Exception:
    pass
" 2>/dev/null) || TEXT=''

[ -z "$CHAT_ID" ] && exit 0
[ -z "$TEXT" ] && exit 0

# Skip if the model already attached a file (avoid double-audio)
HAS_FILES=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    files = ti.get('files', [])
    print('1' if files else '0')
except Exception:
    print('0')
" 2>/dev/null) || HAS_FILES='0'

[ "${HAS_FILES}" = "1" ] && exit 0

# Find bot token
TOKEN=''
if [ -n "${TELEGRAM_STATE_DIR:-}" ] && [ -f "$TELEGRAM_STATE_DIR/.env" ]; then
    TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$TELEGRAM_STATE_DIR/.env" 2>/dev/null | cut -d= -f2-)
fi
if [ -z "$TOKEN" ]; then
    for dir in "$HOME"/apex/agents/*/telegram; do
        [ -f "$dir/.env" ] || continue
        T=$(grep "^TELEGRAM_BOT_TOKEN=" "$dir/.env" 2>/dev/null | cut -d= -f2-)
        if [ -n "$T" ]; then TOKEN="$T"; break; fi
    done
fi
[ -z "$TOKEN" ] && exit 0

# Generate TTS
AUDIO_PATH=$(bash /home/barry/projects/claudeteam/bin/tg-say.sh "$TEXT" 2>/dev/null) || exit 0
[ -z "$AUDIO_PATH" ] || [ ! -f "$AUDIO_PATH" ] && exit 0

# Send audio as voice note
curl -s --max-time 60 \
    "https://api.telegram.org/bot${TOKEN}/sendVoice" \
    -F "chat_id=${CHAT_ID}" \
    -F "voice=@${AUDIO_PATH}" \
    >/dev/null 2>&1 || true

exit 0
