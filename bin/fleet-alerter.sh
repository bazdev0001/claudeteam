#!/usr/bin/env bash
# fleet-alerter — DMs Barry on Telegram whenever the bridge-guardian heals (or fails to heal) a node.
#
# Deliberately DECOUPLED from tc-bridge-guardian: it only READS the guardian's journal output and
# sends notifications. It can never slow, block, or crash the guardian or the channel sessions.
# Separation of concerns = the alerter can die or be restarted with zero impact on healing.
#
# How: the guardian appends event lines to today's vault journal, e.g.
#   "✅ guardian: tc2(Sage/telegram) restarted, bridge back up"
#   "❌ guardian: ... restart did NOT restore bridge — manual check needed"
# We tail the journal from a saved byte offset every few seconds and alert on the OUTCOME lines
# (one message per heal event, carrying the result). Raw Bot API call works even if a bridge is
# down (plain outbound HTTPS, independent of the channel plugin).
set -uo pipefail

NOTIFY_ENV="/home/barry/.claude/channels/telegram/.env"            # tc1/Athena bot = the alerter
NOTIFY_ACCESS="/home/barry/.claude/channels/telegram/access.json"  # Barry's DM id (allowFrom)
STATE="/tmp/fleet-alerter.state"   # "YYYY-MM-DD <byteoffset>"
BEAT="/tmp/fleet-alerter.log"
INTERVAL=5

journal_for() { echo "/home/barry/projects/obsidian/journal/$1.md"; }

send() {
  local text="$1" token chat
  token=$(grep -oE 'TELEGRAM_BOT_TOKEN=.*' "$NOTIFY_ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "'"'"'\r\n')
  chat=$(grep -oE '[0-9]{6,}' "$NOTIFY_ACCESS" 2>/dev/null | head -1)
  if [[ -z "$token" || -z "$chat" ]]; then
    echo "[$(date +%F\ %T)] NO token/chat — cannot send: $text" >> "$BEAT"; return 0
  fi
  curl -s --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1 \
    && echo "[$(date +%F\ %T)] sent: $text" >> "$BEAT" \
    || echo "[$(date +%F\ %T)] SEND FAILED: $text" >> "$BEAT"
}

# init state to END of today's journal so we don't replay old events on first start
today=$(date +%F)
if [[ -f "$STATE" ]]; then
  read -r s_date s_off < "$STATE"
else
  s_date="$today"; s_off=$(wc -c < "$(journal_for "$today")" 2>/dev/null || echo 0)
  echo "$s_date $s_off" > "$STATE"
fi
echo "[$(date +%F\ %T)] fleet-alerter started (watching guardian heal events)" >> "$BEAT"

while true; do
  today=$(date +%F)
  jf=$(journal_for "$today")
  # day rollover → start from 0 on the new file
  if [[ "$s_date" != "$today" ]]; then s_date="$today"; s_off=0; fi
  [[ -f "$jf" ]] || { sleep "$INTERVAL"; continue; }

  size=$(wc -c < "$jf" 2>/dev/null || echo 0)
  if (( size > s_off )); then
    # read only the newly-appended bytes
    new=$(tail -c +$((s_off + 1)) "$jf" 2>/dev/null)
    s_off="$size"
    while IFS= read -r line; do
      case "$line" in
        *"✅ guardian:"*"bridge back up"*)
          node=$(echo "$line" | grep -oE '[a-z0-9]+\([A-Za-z]+/[a-z]+\)' | head -1)
          send "✅ Fleet self-healed: ${node:-a node}'s bridge had died — auto-restarted, back online. (no action needed)"
          ;;
        *"✅ guardian:"*"service was down"*)
          node=$(echo "$line" | grep -oE '[a-z0-9]+\([A-Za-z]+/[a-z]+\)' | head -1)
          send "✅ Fleet self-healed: ${node:-a node} service was down — auto-restarted. (no action needed)"
          ;;
        *"❌ guardian:"*)
          node=$(echo "$line" | grep -oE '[a-z0-9]+\([A-Za-z]+/[a-z]+\)' | head -1)
          send "🚨 Fleet: ${node:-a node} auto-restart FAILED — needs manual check: run fleet-status, then systemctl --user restart the service."
          ;;
      esac
    done <<< "$new"
  fi
  echo "$s_date $s_off" > "$STATE"
  sleep "$INTERVAL"
done
