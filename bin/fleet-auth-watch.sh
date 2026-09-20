#!/usr/bin/env bash
# fleet-auth-watch.sh — Claude OAuth credential early-warning monitor (fleet-wide).
#
# WHY (2026-09-19): Helen (VPS) was mute Sep 9→19 because her OAuth *refresh* token
# expired; the CLI wiped tokens and sessions emitted synthetic "Not logged in" turns
# while the Telegram poller kept acking, so watchdog v3 stayed green for 10 days.
# This watcher predicts that failure days ahead and detects a mute brain within 1h.
#
# REPLACES (on the VPS): fleet-token-refresh-watch.{service,timer} — broken-by-design:
# it checked ~/.claude/auth/tokens.json (a path that never existed) and curled a
# nonexistent api.anthropic.com/v1/auth/refresh endpoint. Disabled 2026-09-19.
#
# WHAT IT DOES (hourly via fleet-auth-watch.timer, runs as the service user):
#   1. Reads ~/.claude/.credentials.json → remaining life of access token (8h,
#      auto-refreshes while claude runs) and refresh token (~30d from login; the
#      one whose death requires an interactive re-login).
#   2. Brain probe: `claude -p "pong" --model haiku` with a 60s timeout — catches
#      auth-dead and other mute states regardless of what the file claims. As a
#      side effect this also triggers the CLI's own access-token refresh.
#   3. Alerts Barry on Telegram when:
#        a) refresh token expires within WARN_DAYS (7) — one reminder per day
#        b) refresh token expired / credentials missing or empty — critical,
#           at most once every 4h
#        c) brain probe fails — critical, at most once every 4h
#      Otherwise: silent (log line only, no Telegram spam).
#
# Transport: reuses each box's established Telegram pattern — mini PC: fleet-node-lib.sh
# fleet_alert (token from the live channel unit's Environment=); VPS: Helen's
# /home/barry/apex/agents/helen/telegram/.env (same source helen-tg.sh uses).
# No secrets are hardcoded here.
#
# Usage: fleet-auth-watch.sh [--test]   # --test sends one labeled TEST alert and exits

set -uo pipefail

CREDS="$HOME/.claude/.credentials.json"
LOG="$HOME/logs/fleet-auth-watch.log"
STATE_DIR="$HOME/.cache/fleet-auth-watch"
WARN_DAYS=7
CRIT_COOLDOWN_S=$((4 * 3600))
PROBE_TIMEOUT=60
CHAT_ID=6062064959   # Barry (matches FLEET_CHAT_ID / helen-tg.sh)

mkdir -p "$(dirname "$LOG")" "$STATE_DIR" 2>/dev/null
log() { echo "$(TZ=America/Los_Angeles date '+%F %T %Z') $*" >> "$LOG"; }

# ---- node detection + Telegram send (reuse existing per-box patterns) ----
MINIPC_LIB="/home/barry/projects/claudeteam/bin/fleet-node-lib.sh"
HELEN_ENV="/home/barry/apex/agents/helen/telegram/.env"

if [[ -f "$MINIPC_LIB" ]]; then
  NODE="Sage (mini PC)"; NODE_SHORT="sage"
  # shellcheck source=/dev/null
  source "$MINIPC_LIB"
  send_alert() { fleet_alert sage "$1"; }
elif [[ -f "$HELEN_ENV" ]]; then
  NODE="Helen (VPS)"; NODE_SHORT="helen"
  send_alert() {
    local token
    token=$(grep -oE 'TELEGRAM_BOT_TOKEN=.*' "$HELEN_ENV" | head -1 | cut -d= -f2- | tr -d ' "'"'"'\r\n')
    [[ -n "$token" ]] || { log "ALERT-FAILED (no token in $HELEN_ENV): $1"; return 1; }
    local http
    http=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
      "https://api.telegram.org/bot${token}/sendMessage" \
      -d "chat_id=${CHAT_ID}" --data-urlencode "text=$1" 2>/dev/null) || http=000
    if [[ "$http" == "200" ]]; then log "alert sent: $1"; else log "ALERT-FAILED (http=$http): $1"; return 1; fi
  }
else
  NODE="$(hostname)"; NODE_SHORT="$(hostname)"
  send_alert() { log "ALERT-FAILED (no transport configured): $1"; return 1; }
fi

FIX_LINE="Fix: Sage can run the remote login flow — just reply 'fix ${NODE_SHORT} login'."

# ---- read credentials ----
now_ms=$(($(date +%s) * 1000))
read -r access_ms refresh_ms < <(python3 - "$CREDS" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1])).get("claudeAiOauth", {})
    print(int(d.get("expiresAt") or 0), int(d.get("refreshTokenExpiresAt") or 0))
except Exception:
    print(0, 0)
PYEOF
) || { access_ms=0; refresh_ms=0; }

pst() { TZ=America/Los_Angeles date -d "@$(( ${1:-0} / 1000 ))" '+%a %b %-d, %-I:%M %p %Z'; }
refresh_left_s=$(( (refresh_ms - now_ms) / 1000 ))
access_left_s=$(( (access_ms - now_ms) / 1000 ))
refresh_left_d=$(awk "BEGIN{printf \"%.1f\", $refresh_left_s/86400}")
access_left_h=$(awk "BEGIN{printf \"%.1f\", $access_left_s/3600}")

# ---- brain probe ----
CLAUDE_BIN=$(command -v claude || echo /home/barry/.npm-global/bin/claude)
probe_out=$(timeout "$PROBE_TIMEOUT" "$CLAUDE_BIN" -p "pong" --model haiku 2>&1)
probe_rc=$?
probe_ok=1
if [[ $probe_rc -ne 0 || -z "${probe_out// /}" ]] \
   || grep -qiE 'not logged in|log ?in|invalid api key|authentication|credential|oauth' <<<"$probe_out"; then
  probe_ok=0
fi

status="[$NODE_SHORT] refresh=${refresh_left_d}d left (exp $(pst "$refresh_ms")), access=${access_left_h}h left, probe=$([[ $probe_ok == 1 ]] && echo OK || echo FAIL rc=$probe_rc)"
log "$status"

# ---- test mode ----
if [[ "${1:-}" == "--test" ]]; then
  send_alert "🧪 TEST — ignore. [$NODE] fleet-auth-watch Telegram path verified. Live status: refresh token ${refresh_left_d}d left (expires $(pst "$refresh_ms")), access ${access_left_h}h left, brain probe $([[ $probe_ok == 1 ]] && echo OK || echo FAILED)."
  echo "$status (TEST alert sent)"
  exit 0
fi

# ---- alert policy ----
crit_ok_to_send() {  # at most one critical alert per 4h
  local stamp="$STATE_DIR/crit-last" last=0 now; now=$(date +%s)
  [[ -f "$stamp" ]] && last=$(<"$stamp")
  (( now - last >= CRIT_COOLDOWN_S )) || return 1
  echo "$now" > "$stamp"
}

if [[ ! -f "$CREDS" || "$refresh_ms" == "0" ]]; then
  log "CRITICAL: credentials missing/empty"
  crit_ok_to_send && send_alert "🚨 [$NODE] Claude credentials MISSING or empty ($CREDS) — the agent brain is not logged in and will be mute. $FIX_LINE"
elif (( refresh_left_s <= 0 )); then
  log "CRITICAL: refresh token EXPIRED at $(pst "$refresh_ms")"
  crit_ok_to_send && send_alert "🚨 [$NODE] Claude refresh token EXPIRED at $(pst "$refresh_ms") — agent cannot re-auth and will go mute (this is what silenced Helen Sep 9-19). $FIX_LINE"
elif (( probe_ok == 0 )); then
  log "CRITICAL: brain probe failed rc=$probe_rc out=$(head -c 300 <<<"$probe_out" | tr '\n' ' ')"
  crit_ok_to_send && send_alert "🚨 [$NODE] Claude brain probe FAILED (claude -p returned rc=$probe_rc) even though tokens look present — agent may be mute. First output line: $(head -1 <<<"$probe_out" | head -c 200). $FIX_LINE"
elif (( refresh_left_s < WARN_DAYS * 86400 )); then
  today=$(TZ=America/Los_Angeles date +%F)
  if [[ "$(cat "$STATE_DIR/warn-day" 2>/dev/null)" != "$today" ]]; then
    echo "$today" > "$STATE_DIR/warn-day"
    send_alert "⚠️ [$NODE] Claude refresh token expires in ${refresh_left_d} days — $(pst "$refresh_ms"). After that the agent goes mute until an interactive re-login. $FIX_LINE (Daily reminder until re-login.)"
    log "WARN sent: refresh ${refresh_left_d}d left"
  else
    log "WARN window but already reminded today"
  fi
fi

echo "$status"
exit 0
