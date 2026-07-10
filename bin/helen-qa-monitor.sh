#!/usr/bin/env bash
# Continuous Helen health check — Claude Code channel model (updated 2026-07-10).
# Helen PRIMARY runs as claude-helen-barry-telegram.service under barry user on VPS.
# NOTE: helen apex user services DISABLED 2026-07-10 (helen-discord retired 2026-07-09).
# Runs every 5 min via helen-qa-monitor.timer on the mini-PC (SSH probe).
# FAIL -> Telegram alert (max 1/30min).

set -uo pipefail
VPS="barry@srv1601002.hstgr.cloud"
STATUS="$HOME/.cache/helen-qa-status"
ALERTED="$HOME/.cache/helen-qa-alerted"
LOG="$HOME/.cache/helen-qa-monitor.log"
ENV_FILE="$HOME/.claude/channels/telegram-tc2/.env"
CHAT_ID="6062064959"

now=$(date +%s)
report=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$VPS" '
br=$(systemctl --user is-active claude-helen-barry-telegram.service 2>/dev/null || echo "inactive")
echo "telegram=$br"
' 2>/dev/null) || report="ssh_failed"

echo "$(date '+%F %T') $report" >> "$LOG"

fails=()
if [[ "$report" == "ssh_failed" ]]; then
  fails+=("VPS unreachable over SSH")
else
  [[ "$report" == *"telegram=active"* ]] || fails+=("claude-helen-barry-telegram not active")
fi

if [ ${#fails[@]} -eq 0 ]; then
  echo "$(date '+%F %T') OK — $report" > "$STATUS"; exit 0
fi

echo "$(date '+%F %T') FAIL — ${fails[*]} — $report" > "$STATUS"
last_alert=$(stat -c %Y "$ALERTED" 2>/dev/null || echo 0)
(( now - last_alert >= 1800 )) || exit 0
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || exit 0
curl -s --max-time 5 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode "text=🔴 Helen: ${fails[*]} — investigating." >/dev/null 2>&1 || true
touch "$ALERTED"
