#!/usr/bin/env bash
# Continuous Helen health check — Claude Code channel model (updated 2026-07-10).
# Helen PRIMARY runs as claude-helen-barry-telegram.service under barry user on VPS.
# NOTE: helen apex user services DISABLED 2026-07-10 (helen-discord retired 2026-07-09).
# Runs every 5 min via helen-qa-monitor.timer on the mini-PC (SSH probe).
# LOG-ONLY since 2026-07-24 (Barry: no Helen messages). Status file feeds the
# 06:00/21:00 fleet status report; auto-cleanup still runs.

set -uo pipefail
VPS="barry@srv1601002.hstgr.cloud"
STATUS="$HOME/.cache/helen-qa-status"
ALERTED="$HOME/.cache/helen-qa-alerted"
LOG="$HOME/.cache/helen-qa-monitor.log"
ENV_FILE="$HOME/apex/agents/sage/telegram/.env"
CHAT_ID="6062064959"

now=$(date +%s)
report=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$VPS" '
br=$(systemctl --user is-active claude-helen-barry-telegram.service 2>/dev/null || echo "inactive")
disk=$(df / 2>/dev/null | awk "NR==2 {print \$5}" | tr -d "%")
echo "telegram=$br disk=${disk:-unknown}"
' 2>/dev/null) || report="ssh_failed"

echo "$(date '+%F %T') $report" >> "$LOG"

fails=()
if [[ "$report" == "ssh_failed" ]]; then
  fails+=("VPS unreachable over SSH")
else
  [[ "$report" == *"telegram=active"* ]] || fails+=("claude-helen-barry-telegram not active")
  disk_pct=$(sed -n 's/.*disk=\([0-9]\+\).*/\1/p' <<< "$report")
  if [[ -n "$disk_pct" && "$disk_pct" -ge 90 ]]; then
    # Safe auto-cleanup BEFORE alerting (2026-07-17): journal vacuum + apt clean +
    # stale /tmp, via apex (passwordless sudo). Max once/day; alert only if still >=90.
    CLEAN_STAMP="$HOME/.cache/helen-qa-cleanup-day"
    if [[ "$(cat "$CLEAN_STAMP" 2>/dev/null)" != "$(date +%F)" ]]; then
      date +%F > "$CLEAN_STAMP"
      ssh -o BatchMode=yes -o ConnectTimeout=15 apex@srv1601002.hstgr.cloud \
        'sudo -n journalctl --vacuum-size=150M; sudo -n apt-get clean; sudo -n find /tmp -mindepth 1 -type f -mtime +7 -delete' \
        >/dev/null 2>&1
      disk_pct=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$VPS" \
        'df / | awk "NR==2 {print \$5}" | tr -d "%"' 2>/dev/null)
      echo "$(date '+%F %T') ran VPS auto-cleanup — disk now ${disk_pct:-unknown}%" >> "$LOG"
    fi
    [[ -n "$disk_pct" && "$disk_pct" -ge 90 ]] && fails+=("VPS disk ${disk_pct}% full (>=90% even after auto-cleanup)")
  fi
fi

if [ ${#fails[@]} -eq 0 ]; then
  echo "$(date '+%F %T') OK — $report" > "$STATUS"; exit 0
fi

echo "$(date '+%F %T') FAIL — ${fails[*]} — $report" > "$STATUS"
# Telegram alert removed 2026-07-24 (Barry: stop Helen messages) — failures now
# surface only via $STATUS in the twice-daily fleet status report.
