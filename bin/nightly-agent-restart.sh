#!/usr/bin/env bash
# nightly-agent-restart.sh — 1:00am PST daily (claudeteam-reset.timer, moved from 04:00).
# Barry's rule 2026-07-18: restart each channel agent ONLY if it is not mid-task, so it
# reloads all new updates (rules, scripts, memory). Busy agents are retried every 10 min
# until ~2:30am, then left alone until tomorrow.
#
# Busy definition (same signals as bin/tc-intelligent-reset.sh, inverted):
#   - GLOBAL busy: any session JSONL in the shared claudeteam project dir written in the
#     last IDLE_SECS (a brain is actively producing output; the dir is shared by all four
#     sessions, so we stay conservative and hold off on everyone).
#   - PER-SERVICE busy: newest inbox message is NEWER than the newest JSONL write
#     (a message is waiting/unanswered for that agent).
# DRY_RUN=1 -> single pass, prints decisions, restarts nothing.
set -uo pipefail

LOG="$HOME/.cache/nightly-agent-restart.log"
JSONL_DIR="$HOME/.claude/projects/-home-barry-projects-claudeteam"
IDLE_SECS=300      # transcript quiet this long = brain idle
RETRY_GAP=600      # 10 min between attempts
MAX_TRIES=10       # 1:00am .. ~2:30am
DRY_RUN="${DRY_RUN:-0}"

# service|inbox (same node map as tc-intelligent-reset.sh)
NODES=(
  "claudeteam-channel-tc2.service|$HOME/apex/agents/sage/telegram/inbox"
  "claudeteam-channel.service|$HOME/apex/agents/athena/telegram/inbox"
  "claudeteam-channel-discord-sage.service|$HOME/apex/agents/sage/discord/inbox"
  "claudeteam-channel-discord-athena.service|$HOME/apex/agents/athena/discord/inbox"
)

mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; [ "$DRY_RUN" = "1" ] && echo "$*"; }

newest_mtime(){ find "$1" -maxdepth 1 -type f ${2:+-name "$2"} -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1; }

declare -A done
handled=0
for ((try=1; try<=MAX_TRIES; try++)); do
  now=$(date +%s)
  newest_jsonl=$(newest_mtime "$JSONL_DIR" '*.jsonl'); newest_jsonl=${newest_jsonl:-0}

  if (( now - newest_jsonl < IDLE_SECS )); then
    log "try $try: GLOBAL BUSY — transcript written $((now-newest_jsonl))s ago (<${IDLE_SECS}s); holding all restarts"
    if [ "$DRY_RUN" = "1" ]; then  # still show per-service inbox state for visibility
      for node in "${NODES[@]}"; do
        svc="${node%%|*}"; inbox="${node##*|}"
        newest_inbox=$(newest_mtime "$inbox"); newest_inbox=${newest_inbox:-0}
        if (( newest_inbox > newest_jsonl )); then
          log "        $svc: pending inbox msg (newer than last transcript write) -> would stay BUSY"
        else
          log "        $svc: inbox quiet -> would be IDLE once transcripts settle"
        fi
      done
    fi
  else
    for node in "${NODES[@]}"; do
      svc="${node%%|*}"; inbox="${node##*|}"
      [ -n "${done[$svc]:-}" ] && continue
      if ! systemctl --user is-active --quiet "$svc"; then
        log "try $try: $svc not active — skipping (guardian/intelligent-reset owns dead services)"
        done[$svc]=1; continue
      fi
      newest_inbox=$(newest_mtime "$inbox"); newest_inbox=${newest_inbox:-0}
      if (( newest_inbox > newest_jsonl )); then
        log "try $try: $svc BUSY — inbox msg newer than last transcript write (pending work)"
        continue
      fi
      if [ "$DRY_RUN" = "1" ]; then
        log "try $try: $svc IDLE — DRY-RUN: would journal-backup + restart"
      else
        log "try $try: $svc IDLE — restarting (nightly 1am reload of rules/scripts/memory)"
        /bin/bash "$HOME/projects/claudeteam/bin/journal-new-backup.sh" "nightly-1am-reset: $svc" >>"$LOG" 2>&1 || true
        systemctl --user restart "$svc" >>"$LOG" 2>&1
      fi
      done[$svc]=1; handled=$((handled+1))
    done
  fi

  (( handled == ${#NODES[@]} )) && { log "all ${#NODES[@]} services handled after $try tries"; exit 0; }
  [ "$DRY_RUN" = "1" ] && { log "DRY-RUN: single pass done ($handled/${#NODES[@]} would be handled)"; exit 0; }
  sleep "$RETRY_GAP"
done
log "gave up after $MAX_TRIES tries — still busy: $(for n in "${NODES[@]}"; do s=${n%%|*}; [ -z "${done[$s]:-}" ] && printf '%s ' "$s"; done)"
exit 0
