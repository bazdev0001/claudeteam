#!/usr/bin/env bash
# monitor-manifest-audit.sh — "built != deployed" enforcement (2026-07-17).
# Reads bin/monitor-manifest.txt (host|unit-or-task|max-age-minutes) and verifies each
# monitor is ENABLED and actually RAN within max-age, using real evidence:
#   minipc     : systemctl --user is-enabled + LastTriggerUSec (.timer) / is-active (.service, age 0)
#   windows    : schtasks.exe Last Run Time + Last Result 0 + task enabled
#   vps-barry  : ssh vps -> sudo -u barry systemctl --user (same checks)
#   vps-apex   : ssh vps -> systemctl --user (apex is the login user)
# Failures -> Telegram alert to Barry via Sage's bot, max 1/day (latch file).
# Env: MANIFEST_AUDIT_TEST=1 labels alert as test + bypasses the daily latch.
set -uo pipefail

MANIFEST="/home/barry/projects/claudeteam/bin/monitor-manifest.txt"
ENV_FILE="$HOME/apex/agents/sage/telegram/.env"
CHAT_ID="6062064959"
LOG="$HOME/logs/monitor-manifest-audit.log"
LATCH="$HOME/.cache/monitor-manifest-alerted"
SCHTASKS="/mnt/c/Windows/System32/schtasks.exe"
mkdir -p "$HOME/logs" "$HOME/.cache"

now=$(date +%s)
fails=()
ok=0

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# ts_ok <epoch-string-or-date> <max-age-min>  -> 0 if parseable and fresh
age_ok() {
  local when="$1" max_min="$2" ts
  ts=$(date -d "$when" +%s 2>/dev/null) || return 1
  (( now - ts <= max_min * 60 ))
}

check_systemd() {  # $1=prefix-cmd (may be empty), $2=unit, $3=max-age-min
  local pre="$1" unit="$2" max="$3" en act last
  en=$($pre systemctl --user is-enabled "$unit" 2>/dev/null | tr -d '[:space:]')
  case "$en" in enabled|static|linked) ;; *) echo "not enabled ($en:-missing)"; return ;; esac
  if [[ "$unit" == *.timer ]]; then
    act=$($pre systemctl --user is-active "$unit" 2>/dev/null | tr -d '[:space:]')
    [[ "$act" == active ]] || { echo "timer not active ($act)"; return; }
    last=$($pre systemctl --user show "$unit" -p LastTriggerUSec --value 2>/dev/null | tr -d '\r')
    [[ -n "$last" && "$last" != "n/a" ]] || { echo "never triggered"; return; }
    age_ok "$last" "$max" || { echo "stale — last trigger $last (max ${max}m)"; return; }
  else
    act=$($pre systemctl --user is-active "$unit" 2>/dev/null | tr -d '[:space:]')
    [[ "$act" == active ]] || { echo "service not active ($act)"; return; }
  fi
  echo OK
}

check_windows() {  # $1=task-name, $2=max-age-min
  local task="$1" max="$2" out lastrun result state
  # </dev/null: schtasks.exe otherwise slurps the manifest from the loop's stdin
  out=$("$SCHTASKS" /query /tn "$task" /v /fo LIST </dev/null 2>/dev/null | tr -d '\r') || { echo "task not found"; return; }
  state=$(sed -n 's/^Scheduled Task State: *//p' <<<"$out" | head -1)
  [[ "$state" == "Enabled" ]] || { echo "task state: ${state:-unknown}"; return; }
  result=$(sed -n 's/^Last Result: *//p' <<<"$out" | head -1)
  [[ "$result" == "0" ]] || { echo "last result $result"; return; }
  lastrun=$(sed -n 's/^Last Run Time: *//p' <<<"$out" | head -1)
  age_ok "$lastrun" "$max" || { echo "stale — last run $lastrun (max ${max}m)"; return; }
  echo OK
}

# ssh -n is REQUIRED: without it ssh slurps the manifest from the loop's stdin.
VPS_PRE="ssh -n -o ConnectTimeout=15 vps"
VPS_BARRY_PRE=""
if grep -q '^vps-barry|' "$MANIFEST"; then
  BARRY_UID=$(ssh -n -o ConnectTimeout=15 vps 'id -u barry' 2>/dev/null | tr -d '[:space:]')
  [[ -n "$BARRY_UID" ]] && VPS_BARRY_PRE="$VPS_PRE sudo -n -u barry XDG_RUNTIME_DIR=/run/user/${BARRY_UID}"
fi

while IFS='|' read -r host name max; do
  [[ -z "$host" || "$host" == \#* ]] && continue
  host=$(tr -d '[:space:]' <<<"$host"); name=$(tr -d '[:space:]' <<<"$name"); max=$(tr -d '[:space:]' <<<"$max")
  case "$host" in
    minipc)    verdict=$(check_systemd "" "$name" "$max") ;;
    windows)   verdict=$(check_windows "$name" "$max") ;;
    vps-barry) if [[ -n "$VPS_BARRY_PRE" ]]; then verdict=$(check_systemd "$VPS_BARRY_PRE" "$name" "$max"); else verdict="ssh/uid lookup for barry@vps failed"; fi ;;
    vps-apex)  verdict=$(check_systemd "$VPS_PRE" "$name" "$max") ;;
    *)         verdict="unknown host '$host'" ;;
  esac
  if [[ "$verdict" == OK ]]; then
    ok=$((ok+1))
  else
    fails+=("$host/$name: $verdict")
  fi
done < "$MANIFEST"

if [ ${#fails[@]} -eq 0 ]; then
  log "PASS — all $ok monitors enabled + fresh"
  [ -f "$LATCH" ] && rm -f "$LATCH"
  exit 0
fi

log "FAIL — $ok ok, ${#fails[@]} failing: ${fails[*]}"

# Max 1 alert/day (unless test mode)
if [ -z "${MANIFEST_AUDIT_TEST:-}" ] && [ -f "$LATCH" ] && [ "$(cat "$LATCH" 2>/dev/null)" == "$(date +%F)" ]; then
  exit 1
fi

label="🔴"
[ -n "${MANIFEST_AUDIT_TEST:-}" ] && label="🧪 TEST ALERT (ignore)"
msg="$label [monitor-manifest-audit @ mini-PC, via Sage's bot] ${#fails[@]} monitor(s) not deployed/running:"
for f in "${fails[@]}"; do msg+=$'\n'"- $f"; done
msg+=$'\n'"Fix: schedule/enable the unit, verify first run, keep bin/monitor-manifest.txt honest."

# Token: the .env this used to source does not exist on the mini-PC, so this audit has been
# logging "no bot token — cannot alert" and silently swallowing every failure it found since at
# least 2026-09-07 (verified 2026-09-15 in ~/logs/monitor-manifest-audit.log). The meta-monitor
# was itself deaf — the exact failure mode it exists to catch. Read the token from Sage's live
# unit Environment= instead; keep the .env path as a fallback for other hosts.
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && [ -r "$HOME/projects/claudeteam/bin/fleet-node-lib.sh" ]; then
  # shellcheck disable=SC1090
  . "$HOME/projects/claudeteam/bin/fleet-node-lib.sh" 2>/dev/null
  TELEGRAM_BOT_TOKEN=$(fleet_node_token sage 2>/dev/null) || TELEGRAM_BOT_TOKEN=''
fi
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" --data-urlencode "text=$msg" >/dev/null 2>&1 \
    && { date +%F > "$LATCH"; log "alert sent (${#fails[@]} failures)"; } \
    || log "alert send FAILED"
else
  log "no bot token — cannot alert"
fi
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
exit 1
