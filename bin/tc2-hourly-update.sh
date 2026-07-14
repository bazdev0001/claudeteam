#!/usr/bin/env bash
# Hourly project report to Barry — filtered, grouped, readable on mobile.

set -uo pipefail
TG_ENV="$HOME/apex/agents/sage/telegram/.env"
CHAT_ID="6062064959"
TRACKER="$HOME/.cache/tc2-project-tracker.txt"
[ -f "$TRACKER" ] || exit 0

TELEGRAM_BOT_TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$TG_ENV" | cut -d= -f2-)
[ -n "$TELEGRAM_BOT_TOKEN" ] || exit 0

# Parse tracker: filter out 100%-complete items, build department sections
declare -a sw=() sites=() vps=() other=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Extract name and percent
  name=$(echo "$line" | cut -d: -f1 | tr -s ' ' | xargs)
  pct=$(echo "$line" | grep -oP '\d+(?=%)' | tail -1)
  [[ -z "$pct" ]] && continue
  [[ "$pct" -eq 100 ]] && continue  # skip completed

  short="${name} (${pct}%)"

  case "$name" in
    voice-messenger|software-factory*|reminder-app|voice-assistance*|myhousecallpro*|outbound-va*|app-improvements|games-research|next-50*|prototypes*)
      sw+=("$short") ;;
    apex-website|apex-agency|apex-law*|dashboard|demos*)
      sites+=("$short") ;;
    scandocs|helen-bridge|helen-endurance|helen-parity)
      vps+=("$short") ;;
    *)
      other+=("$short") ;;
  esac
done < "$TRACKER"

# Build message
hour=$(TZ=America/Los_Angeles date "+%-I:%M%p PDT")
body="🕐 Projects — ${hour}"$'\n'

add_section() {
  local title="$1"; shift
  local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && return
  body+=$'\n'"${title}"$'\n'
  local n=1
  for item in "${items[@]}"; do
    body+="${n}. ${item}"$'\n'
    ((n++))
  done
}

add_section "SOFTWARE" "${sw[@]:-}"
add_section "SITES" "${sites[@]:-}"
add_section "VPS/HELEN" "${vps[@]:-}"
add_section "OTHER" "${other[@]:-}"

helen_qa=$(cat "$HOME/.cache/helen-qa-status" 2>/dev/null | sed 's/^[0-9: -]*//' | cut -c1-60)
[[ -n "${helen_qa:-}" ]] && body+=$'\nHelen: '"${helen_qa}"

curl -s --max-time 8 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode "text=${body}" >/dev/null 2>&1 || true
