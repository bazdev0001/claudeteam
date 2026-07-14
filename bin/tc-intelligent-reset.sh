#!/usr/bin/env bash
# Intelligent frozen-session reset for mini-PC agents — port of the VPS helen-reset.sh
# (see obsidian notes/agent-reliability-standard.md, mechanism 2).
#
# FROZEN = newest inbox message >=15 min old AND no session JSONL write since it
# arrived AND service up >=20 min. Restart with rate cap 3/hour per service.
#
# Caveat: all four sessions share WorkingDirectory=projects/claudeteam, so JSONL
# freshness is project-wide — one busy session can mask another's freeze. That makes
# this check conservative (no false restarts; a masked freeze is caught by the nightly
# claudeteam-reset). Context-full recycling is NOT done here for the same reason.

set -uo pipefail
JSONL_DIR="$HOME/.claude/projects/-home-barry-projects-claudeteam"
LOG="$HOME/.cache/tc-intelligent-reset.log"
STAMPS_DIR="$HOME/.cache/tc-reset-stamps"
FREEZE_AGE=900
MIN_UPTIME=1200
MAX_PER_HOUR=3

# service|inbox
NODES=(
  "claudeteam-channel-tc2.service|$HOME/apex/agents/sage/telegram/inbox"
  "claudeteam-channel.service|$HOME/apex/agents/athena/telegram/inbox"
  "claudeteam-channel-discord.service|$HOME/.claude/channels/discord/inbox"
  "claudeteam-channel-discord-athena.service|$HOME/.claude/channels/discord-athena/inbox"
)

mkdir -p "$STAMPS_DIR" "$(dirname "$LOG")"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

now=$(date +%s)
newest_jsonl=$(find "$JSONL_DIR" -maxdepth 1 -name '*.jsonl' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)

for entry in "${NODES[@]}"; do
  svc="${entry%%|*}"; inbox="${entry#*|}"
  systemctl --user is-active --quiet "$svc" || continue
  [[ -d "$inbox" ]] || continue

  enter=$(systemctl --user show "$svc" --property=ActiveEnterTimestamp --value)
  enter_s=$(date -d "$enter" +%s 2>/dev/null || echo 0)
  (( now - enter_s >= MIN_UPTIME )) || continue

  newest_inbox=$(find "$inbox" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
  [[ -n "${newest_inbox:-}" && -n "${newest_jsonl:-}" ]] || continue
  (( now - newest_inbox >= FREEZE_AGE )) || continue
  (( newest_jsonl < newest_inbox )) || continue

  stamps="$STAMPS_DIR/${svc}.stamps"; touch "$stamps"
  recent=$(awk -v c=$((now-3600)) '$1>c' "$stamps" | wc -l)
  if (( recent >= MAX_PER_HOUR )); then
    log "SKIP $svc frozen but rate cap ${MAX_PER_HOUR}/h reached"
    continue
  fi

  log "RESTART $svc: FROZEN (msg waited $(( (now-newest_inbox)/60 ))min, no session activity since)"
  echo "$now" >> "$stamps"
  systemctl --user restart "$svc"
done
