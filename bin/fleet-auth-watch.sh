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
#   3. Publishes this host's auth status into the GitHub-synced vault:
#      obsidian/notes/auth-status/<host>.md (ONE FILE PER HOST — deliberately, so
#      the 5-min vault git sync never merge-conflicts on a shared table; the
#      overview lives at obsidian/notes/FLEET-AUTH-STATUS.md which transcludes
#      the per-host files). The existing vault sync engines push it to GitHub
#      (mini PC: apex-obsidian-sync.timer; VPS: vault-sync.timer) — no git here.
#   4. Telegram-alerts Barry (schedule per Barry 2026-09-19):
#        - refresh token < 7 days left  → one quiet reminder per day
#        - refresh token < 6 hours left → alert EVERY HOUR until re-login
#        - refresh token expired / credentials missing/empty / brain probe fails
#          → immediate alert, repeated EVERY HOUR until fixed
#      Otherwise: silent (log + status file only, no Telegram spam).
#
# Transport: reuses each box's established Telegram pattern — mini PC: fleet-node-lib.sh
# fleet_alert (token from the live channel unit's Environment=); VPS: Helen's
# /home/barry/apex/agents/helen/telegram/.env (same source helen-tg.sh uses).
# No secrets are hardcoded here, and none may ever be written into the vault.
#
# Usage: fleet-auth-watch.sh [--test]   # --test sends one labeled TEST alert and exits

set -uo pipefail

CREDS="$HOME/.claude/.credentials.json"
CLAUDE_JSON="$HOME/.claude.json"
LOG="$HOME/logs/fleet-auth-watch.log"
STATE_DIR="$HOME/.cache/fleet-auth-watch"
VAULT="/home/barry/projects/obsidian"
WARN_DAYS=7
URGENT_HOURS=6
PROBE_TIMEOUT=60
CHAT_ID=6062064959   # Barry (matches FLEET_CHAT_ID / helen-tg.sh)

mkdir -p "$(dirname "$LOG")" "$STATE_DIR" 2>/dev/null
log() { echo "$(TZ=America/Los_Angeles date '+%F %T %Z') $*" >> "$LOG"; }

# ---- node detection + Telegram send (reuse existing per-box patterns) ----
MINIPC_LIB="/home/barry/projects/claudeteam/bin/fleet-node-lib.sh"
HELEN_ENV="/home/barry/apex/agents/helen/telegram/.env"

if [[ -f "$MINIPC_LIB" ]]; then
  NODE_NAME="Sage"; HOST_LABEL="mini PC"; NODE_SHORT="sage"
  # shellcheck source=/dev/null
  source "$MINIPC_LIB"
  send_alert() { fleet_alert sage "$1"; }
elif [[ -f "$HELEN_ENV" ]]; then
  NODE_NAME="Helen"; HOST_LABEL="VPS"; NODE_SHORT="helen"
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
  NODE_NAME="$(hostname)"; HOST_LABEL="$(hostname)"; NODE_SHORT="$(hostname)"
  send_alert() { log "ALERT-FAILED (no transport configured): $1"; return 1; }
fi

FIX_LINE="reply 'fix ${NODE_SHORT} login' to get the tap-link flow."

# ---- read credentials ----
now_s=$(date +%s); now_ms=$((now_s * 1000))
read -r access_ms refresh_ms < <(python3 - "$CREDS" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1])).get("claudeAiOauth", {})
    print(int(d.get("expiresAt") or 0), int(d.get("refreshTokenExpiresAt") or 0))
except Exception:
    print(0, 0)
PYEOF
) || { access_ms=0; refresh_ms=0; }
ACCOUNT=$(python3 -c "import json;print(json.load(open('$CLAUDE_JSON')).get('oauthAccount',{}).get('emailAddress','?'))" 2>/dev/null || echo "?")

pst()      { TZ=America/Los_Angeles date -d "@$(( ${1:-0} / 1000 ))" '+%a %b %-d, %-I:%M %p %Z'; }
pst_short(){ TZ=America/Los_Angeles date -d "@$(( ${1:-0} / 1000 ))" '+%a %-I:%M %p %Z'; }
left_human() {  # seconds -> "23d 4h" / "5h 12m" / "EXPIRED"
  local s=$1
  if (( s <= 0 )); then echo "EXPIRED"
  elif (( s >= 172800 )); then echo "$(( s/86400 ))d $(( (s%86400)/3600 ))h"
  else echo "$(( s/3600 ))h $(( (s%3600)/60 ))m"; fi
}
refresh_left_s=$(( (refresh_ms - now_ms) / 1000 ))
access_left_s=$(( (access_ms - now_ms) / 1000 ))

# ---- brain probe ----
CLAUDE_BIN=$(command -v claude || echo /home/barry/.npm-global/bin/claude)
probe_out=$(timeout "$PROBE_TIMEOUT" "$CLAUDE_BIN" -p "pong" --model haiku 2>&1)
probe_rc=$?
probe_ok=1
if [[ $probe_rc -ne 0 || -z "${probe_out// /}" ]] \
   || grep -qiE 'not logged in|log ?in|invalid api key|authentication|credential|oauth' <<<"$probe_out"; then
  probe_ok=0
fi
probe_str="$([[ $probe_ok == 1 ]] && echo "OK" || echo "FAIL(rc=$probe_rc)") @ $(TZ=America/Los_Angeles date '+%b %-d %-I:%M %p %Z')"

# ---- classify ----
verdict="✅ healthy"
if [[ ! -f "$CREDS" || "$refresh_ms" == "0" ]]; then verdict="🚨 AUTH DOWN (no credentials)"
elif (( refresh_left_s <= 0 )); then verdict="🚨 AUTH DOWN (refresh token expired)"
elif (( probe_ok == 0 )); then verdict="🚨 BRAIN PROBE FAILING"
elif (( refresh_left_s < URGENT_HOURS * 3600 )); then verdict="🔴 re-login needed <${URGENT_HOURS}h"
elif (( refresh_left_s < WARN_DAYS * 86400 )); then verdict="⚠️ re-login needed in $(left_human $refresh_left_s)"
fi

status="[$NODE_SHORT] refresh=$(left_human $refresh_left_s) left (exp $(pst "$refresh_ms")), access=$(left_human $access_left_s) left, probe=${probe_str}, verdict=${verdict}"
log "$status"

# ---- publish status into the GitHub-synced vault (one file per host: no sync collisions;
#      the existing vault sync timers commit+push it — never run git from here) ----
if [[ -d "$VAULT/notes" ]]; then
  mkdir -p "$VAULT/notes/auth-status" 2>/dev/null
  cat > "$VAULT/notes/auth-status/${NODE_SHORT}.md" <<STEOF
| host | account | refresh-token expires (PST) | access-token expires (PST) | last brain probe | verdict |
|---|---|---|---|---|---|
| ${NODE_NAME} (${HOST_LABEL}) | ${ACCOUNT} | $(pst "$refresh_ms") ($(left_human $refresh_left_s) left) | $(pst "$access_ms") ($(left_human $access_left_s) left) | ${probe_str} | ${verdict} |

Updated $(TZ=America/Los_Angeles date '+%F %T %Z') by fleet-auth-watch on ${NODE_SHORT}. Do not edit — regenerated hourly.
STEOF
else
  log "WARN: vault not found at $VAULT — status file not written"
fi

# ---- test mode ----
if [[ "${1:-}" == "--test" ]]; then
  send_alert "🧪 TEST — ignore. ${NODE_NAME}'s Claude login (${HOST_LABEL}) auth-watch Telegram path verified. Live: refresh token $(left_human $refresh_left_s) left (expires $(pst "$refresh_ms")), access $(left_human $access_left_s) left, brain probe $([[ $probe_ok == 1 ]] && echo OK || echo FAILED)."
  echo "$status (TEST alert sent)"
  exit 0
fi

# ---- alert policy (hourly timer => 'every run' = hourly repeats) ----
case "$verdict" in
  "🚨 AUTH DOWN (no credentials)")
    send_alert "🚨 ${NODE_NAME}'s Claude login (${HOST_LABEL}) is GONE — credentials file missing/empty, the agent brain is mute. To fix: ${FIX_LINE}" ;;
  "🚨 AUTH DOWN (refresh token expired)")
    send_alert "🚨 ${NODE_NAME}'s Claude login (${HOST_LABEL}) EXPIRED at $(pst "$refresh_ms") — agent cannot re-auth and is/will go mute (this is what silenced Helen Sep 9-19). To fix: ${FIX_LINE}" ;;
  "🚨 BRAIN PROBE FAILING")
    send_alert "🚨 ${NODE_NAME}'s Claude brain probe FAILED on ${HOST_LABEL} (claude -p rc=$probe_rc) even though tokens look present — agent may be mute. First line: $(head -1 <<<"$probe_out" | head -c 200). To fix: ${FIX_LINE}" ;;
  "🔴 re-login needed <${URGENT_HOURS}h")
    send_alert "⚠️ ${NODE_NAME}'s Claude login (${HOST_LABEL}) expires in $(left_human $refresh_left_s) ($(pst_short "$refresh_ms")) — ${FIX_LINE} (Hourly reminder until re-login.)" ;;
  "✅ healthy") : ;;
  *)  # 7-day window: one reminder per day
    today=$(TZ=America/Los_Angeles date +%F)
    if [[ "$(cat "$STATE_DIR/warn-day" 2>/dev/null)" != "$today" ]]; then
      echo "$today" > "$STATE_DIR/warn-day"
      send_alert "⚠️ ${NODE_NAME}'s Claude login (${HOST_LABEL}) expires in $(left_human $refresh_left_s) — $(pst "$refresh_ms"). After that the agent goes mute until re-login; ${FIX_LINE} (Daily heads-up; goes hourly at T-${URGENT_HOURS}h.)"
      log "WARN sent: refresh $(left_human $refresh_left_s) left"
    else
      log "WARN window but already reminded today"
    fi ;;
esac

echo "$status"
exit 0
