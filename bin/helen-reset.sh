#!/usr/bin/env bash
# Intelligent context reset for Helen — replaces the broken inline-ExecStart unit
# (old unit had unbalanced quoting -> systemd "bad-setting" -> it NEVER ran, so a
#  frozen or context-full session was never recycled).
#
# Runs every 5 min via claude-helen-reset.timer. Restarts ONLY when:
#   FROZEN : newest inbox msg >=15 min old, no session JSONL write since it
#            arrived, and service up >=20 min (deaf/stuck session)
#   CONTEXT: current session JSONL >= 8 MB (proxy for context nearly full)
# Idle recycling (15 min quiet + 6 h uptime) stays guardian.sh's job — not here,
# so the two never double-restart.
# Rate cap: max 3 resets/hour, then log + skip (prevents restart loops).
# Memory is pushed to git BEFORE any restart so nothing is lost.

set -uo pipefail
SVC="claude-helen-telegram.service"
INBOX="$HOME/.claude/channels/telegram-helen/inbox"
JSONL_DIR="$HOME/.claude/projects/-home-apex-claudeclaw"
LOG="$HOME/claudeclaw/logs/helen-reset.log"
STAMPS="$HOME/.cache/helen-reset-stamps"
MAX_JSONL_MB=8
FREEZE_AGE=900
MIN_UPTIME=1200
MAX_PER_HOUR=3

mkdir -p "$(dirname "$LOG")" "$HOME/.cache"
log(){ echo "$(date -u '+%F %T UTC') $*" >> "$LOG"; }

now=$(date +%s)

touch "$STAMPS"
recent=$(awk -v c=$((now-3600)) '$1>c' "$STAMPS" | wc -l)

enter=$(systemctl --user show "$SVC" --property=ActiveEnterTimestamp --value)
enter_s=$(date -d "$enter" +%s 2>/dev/null || echo 0)
uptime=$(( now - enter_s ))

newest_inbox=$(find "$INBOX" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
newest_jsonl=$(find "$JSONL_DIR" -maxdepth 1 -name '*.jsonl' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
cur_jsonl_mb=$(find "$JSONL_DIR" -maxdepth 1 -name '*.jsonl' -printf '%T@ %s\n' 2>/dev/null | sort -rn | head -1 | awk '{printf "%d", $2/1048576}')

reason=""
if [[ -n "${newest_inbox:-}" && -n "${newest_jsonl:-}" ]] \
   && (( now - newest_inbox >= FREEZE_AGE )) \
   && (( newest_jsonl < newest_inbox )) \
   && (( uptime >= MIN_UPTIME )); then
  reason="FROZEN (msg waited $(( (now-newest_inbox)/60 ))min, no session activity since it arrived)"
elif [[ -n "${cur_jsonl_mb:-}" ]] && (( cur_jsonl_mb >= MAX_JSONL_MB )) \
     && [[ -n "${newest_jsonl:-}" ]] && (( now - newest_jsonl >= 300 )); then
  # only recycle a bloated session at a quiet moment — never mid-task
  reason="CONTEXT-FULL (session jsonl ${cur_jsonl_mb}MB >= ${MAX_JSONL_MB}MB, quiet 5min)"
fi

[[ -z "$reason" ]] && exit 0

if (( recent >= MAX_PER_HOUR )); then
  log "SKIP restart ($reason) — rate cap ${MAX_PER_HOUR}/h reached"
  exit 0
fi

log "RESTART: $reason"
echo "$now" >> "$STAMPS"

bash "$HOME/bin/helen-memory-sync.sh" >/dev/null 2>&1 || true
find "$INBOX" -maxdepth 1 -type f -mmin +120 -delete 2>/dev/null
systemctl --user restart "$SVC"
log "Restart issued"
