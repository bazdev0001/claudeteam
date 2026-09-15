#!/usr/bin/env bash
# fleet-reply-guarantee.sh — mini-PC watcher: "Barry's message was received and never answered."
#
# WHAT GAP THIS CLOSES (ISS-009):
# Every existing mini-PC watchdog is process-level — is the PID alive, is the bridge in the
# cgroup, does the proxy answer /readyz. None of them ask the only question Barry actually
# cares about: did the node REPLY. ISS-009's confirmed root cause (Headroom proxy dying while
# ANTHROPIC_BASE_URL was pinned to it) produced exactly that blind spot: unit "active", bridge
# present, sockets fine, claude alive and retrying — and Barry sat unanswered for up to 13.5h,
# because the terminal "API Error: Connection refused" was emitted as plain assistant TEXT,
# which per the Telegram plugin's contract never reaches his chat.
# The proxy watchdog added to tc-bridge-guardian.sh on 2026-09-02 fixes THAT cause (verified:
# zero recurrences in ~690 sessions Sep 3-15, vs near-daily Aug 16 - Sep 2). This script is the
# independent second layer: it catches the SYMPTOM from any cause — upstream outage, port
# collision, reply-tool deferral, a wedged turn — not just the one we already know about.
#
# SIGNAL: per-node stamps written by fleet-node-stamp.sh from the shared settings.json hooks.
#   last-inbound > last-reply  => a message came in that has not been answered.
#
# WHY IT IS NOT A NAIVE 5-MINUTE TIMER (the false-restart trap):
# Sage and Athena legitimately run long jobs; killing a node mid-task because a research turn
# took 8 minutes would be worse than the bug. So a stuck node must ALSO look like it is not
# making progress: last-activity (any tool call) older than ACTIVE_WINDOW. A node that is
# still running tools is working, and is left alone until HARD_MAX — at which point "no reply
# to Barry in 30 minutes" is a failure regardless of how busy it claims to be.
#
# ACTION: alert Barry from that node's own bot, then restart that node's unit. Both are rate
# limited per node, and the alert is sent BEFORE the restart so he hears about it even if the
# restart itself hangs.
#
# TESTING: DRY_RUN=1 prints what it would do and touches nothing. All thresholds are env
# overridable so a fixture run needs no edits to this file.

set -uo pipefail

LIB="$HOME/projects/claudeteam/bin/fleet-node-lib.sh"
# shellcheck disable=SC1090
. "$LIB" || { echo "fleet-reply-guarantee: cannot source $LIB" >&2; exit 1; }

SOFT_MIN="${SOFT_MIN:-600}"        # 10m unanswered before we even look (normal replies are fast)
HARD_MAX="${HARD_MAX:-1800}"       # 30m unanswered = failure even if the node looks busy
ACTIVE_WINDOW="${ACTIVE_WINDOW:-300}"  # tool call within 5m = "making progress"
BOOT_GRACE="${BOOT_GRACE:-240}"    # ignore a unit that just (re)started — matches guardian
COOLDOWN="${COOLDOWN:-900}"        # max one automated restart per node per 15m
DRY_RUN="${DRY_RUN:-0}"

now=$(date +%s)

for entry in "${FLEET_NODES[@]}"; do
  node="${entry%%|*}"
  unit=$(fleet_node_unit "$node") || continue
  dir=$(fleet_stamp_dir "$node")

  # The guardian owns dead/inactive units; don't double-act on them.
  systemctl --user is-active --quiet "$unit" || continue

  # Boot grace: a freshly restarted session has stale stamps from the previous incarnation.
  enter_s=$(date -d "$(systemctl --user show "$unit" --property=ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
  (( enter_s > 0 && now - enter_s < BOOT_GRACE )) && continue

  inbound=$(fleet_mtime "$dir/last-inbound")
  reply=$(fleet_mtime "$dir/last-reply")
  activity=$(fleet_mtime "$dir/last-activity")

  (( inbound > 0 )) || continue          # nothing ever received on this node
  (( inbound > reply )) || continue       # answered — nothing to do

  age=$(( now - inbound ))
  (( age >= SOFT_MIN )) || continue        # give a normal reply time to happen

  # Stamps predating the current session are not evidence about it.
  (( enter_s > 0 && inbound < enter_s )) && continue

  idle=$(( now - activity ))
  if (( idle < ACTIVE_WINDOW )) && (( age < HARD_MAX )); then
    fleet_log "[$node] unanswered ${age}s but still working (last tool ${idle}s ago) — leaving alone"
    continue
  fi

  # Alert at most once per stuck message (stamp mtime identifies the message).
  flag="$dir/alerted-$inbound"
  if [[ -e "$flag" ]]; then
    continue
  fi

  reason="no tool activity for ${idle}s"
  (( age >= HARD_MAX )) && reason="${age}s with no reply (hard limit)"

  mins=$(( age / 60 ))
  msg="⚠️ Auto-fix: I received your message ${mins} min ago and never replied (${reason}). Restarting myself now — please resend if you don't hear back shortly."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY RUN [$node] WEDGED: age=${age}s idle=${idle}s reason='${reason}' -> would alert + restart $unit"
    continue
  fi

  touch "$flag" 2>/dev/null
  fleet_log "[$node] WEDGED: unanswered ${age}s, ${reason} — alerting + restarting $unit"
  fleet_alert "$node" "$msg" || true

  # Restart cooldown is checked AFTER alerting: Barry should always learn the node is stuck,
  # even on a sweep where we decline to restart it again.
  last_restart=$(fleet_mtime "$dir/last-restart")
  if (( now - last_restart < COOLDOWN )); then
    fleet_log "[$node] restart suppressed — last automated restart $(( now - last_restart ))s ago (<${COOLDOWN}s cooldown)"
    continue
  fi

  touch "$dir/last-restart" 2>/dev/null
  if systemctl --user restart "$unit" 2>>"$FLEET_LOG"; then
    fleet_log "[$node] restarted $unit (reply-guarantee)"
    # Mirror the guardian's journal convention so fleet-alerter.service relays it too.
    echo "[$(TZ=America/Los_Angeles date +%H:%M:%S)] 🔴 guardian: ${node} received a message but never replied (${reason}) — restarted ${unit}" \
      >> "$HOME/projects/obsidian/journal/$(TZ=America/Los_Angeles date +%Y-%m-%d).md" 2>/dev/null
  else
    fleet_log "[$node] RESTART FAILED for $unit"
  fi
done

# Keep the stamp dirs from growing alert flags forever.
find "$FLEET_CACHE" -name 'alerted-*' -mtime +2 -delete 2>/dev/null

exit 0
