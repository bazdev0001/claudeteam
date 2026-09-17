#!/usr/bin/env bash
# minipc-disk-monitor.sh — local disk watch for the mini-PC (WSL).
# Audit 2026-07-17: nobody watched this machine's own disk. Runs every 30 min
# via minipc-disk-monitor.timer. / or /home >=90% -> Telegram alert to Barry
# via Sage's bot (max 1/hour) + log. Test hook: DISK_MONITOR_TEST=1 labels the
# alert as a test; DISK_THRESHOLD overrides the 90% default.

set -uo pipefail
THRESHOLD="${DISK_THRESHOLD:-90}"
ENV_FILE="$HOME/apex/agents/sage/telegram/.env"
CHAT_ID="6062064959"
LOG="$HOME/logs/minipc-disk-monitor.log"
ALERTED="$HOME/.cache/minipc-disk-alerted"

mkdir -p "$HOME/logs" "$HOME/.cache"
now=$(date +%s)
fails=()
seen=""
for mnt in / /home; do
  read -r fs pct <<< "$(df --output=source,pcent "$mnt" 2>/dev/null | awk 'NR==2 {gsub("%",""); print $1, $2}')"
  [ -n "${pct:-}" ] || { fails+=("cannot read df for $mnt"); continue; }
  [[ " $seen " == *" $fs "* ]] && continue   # / and /home on same fs -> report once
  seen="$seen $fs"
  (( pct >= THRESHOLD )) && fails+=("$mnt at ${pct}% (>=${THRESHOLD}%)")
done

if [ ${#fails[@]} -eq 0 ]; then
  [ -f "$ALERTED" ] && { rm -f "$ALERTED"; echo "$(date '+%F %T') RECOVERED — disk below ${THRESHOLD}%" >> "$LOG"; }
  exit 0
fi

echo "$(date '+%F %T') FAIL — ${fails[*]}" >> "$LOG"
last_alert=$(stat -c %Y "$ALERTED" 2>/dev/null || echo 0)
(( now - last_alert >= 3600 )) || exit 0   # max 1 alert/hour

label="🔴"
[ -n "${DISK_MONITOR_TEST:-}" ] && label="🧪 TEST ALERT (ignore)"
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || { echo "$(date '+%F %T') no bot token — cannot alert" >> "$LOG"; exit 1; }
curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode "text=$label [minipc-disk-monitor @ mini-PC, via Sage's bot] Disk: ${fails[*]}. Action: free space in WSL (ncdu /home/barry; docker system prune; apt clean) before the fleet starts failing." >/dev/null 2>&1 || true
touch "$ALERTED"
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
