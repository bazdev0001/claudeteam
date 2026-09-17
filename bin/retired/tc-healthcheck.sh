#!/usr/bin/env bash
# Fleet channel watchdog — dumb cron-style check, run by tc-healthcheck.timer.
# NO agent babysits another agent. This just inspects systemd + process state and restarts.
#
# Detects the "channel plugin bridge drops mid-session" bug: the Claude session process stays
# alive but its transport BRIDGE child (bun run … telegram|discord) dies, leaving the node
# deaf+mute. (That's what silenced Sage/tc2 on 2026-06-24 ~06:00.)
#
# NOT telegram-specific: the same plugin-bridge death can hit a DISCORD node too, so every
# always-on channel session is monitored here — each against the bridge IT is supposed to run.
#
# Per node, restart via `systemctl --user restart` if EITHER:
#   1. the service is not active, OR
#   2. the service is active but its expected transport bridge is missing from its cgroup.
# systemd restart (not nohup start-channel.sh) is what fixes the old
# `exec: claude: not found` failure — systemd carries the correct PATH/env.
#
# Detection reads the service cgroup.procs directly (not `systemctl status` text) so it can't be
# fooled by output truncation or the huge --append-system-prompt cmdlines.
#
# HISTORY: a previous version killed sessions on session-FILE idle age. That false-killed a
# healthy session on 2026-06-24 06:09. Idle-age detection removed; bridge-presence is the real
# signal. 2026-06-24 07:xx: generalised to telegram+discord and cgroup-based detection (Sage).

set -uo pipefail   # NOT -e: one node's failure must never abort the checks for the others

JOURNAL="/home/barry/projects/obsidian/journal/$(date +%Y-%m-%d).md"
HEARTBEAT="/tmp/tc-watchdog.log"   # healthy pings go here, NOT the journal (keeps the journal clean)
CG_BASE="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice"

# node label | systemd unit | bridge cmdline regex it MUST be running
NODES=(
  "tc1(Athena/telegram)|claudeteam-channel.service|bun run.*telegram"
  "tc2(Sage/telegram)|claudeteam-channel-tc2.service|bun run.*telegram"
  "tc2(Sage/discord)|claudeteam-channel-discord.service|bun run.*discord"
  "tc1(Athena/discord)|claudeteam-channel-discord-athena.service|bun run.*discord"
)

log_journal() { echo "[$(date +%H:%M:%S)] $*" >> "$JOURNAL"; }
log_beat()    { echo "[$(date +%F\ %H:%M:%S)] $*" >> "$HEARTBEAT"; }

# bridge_up <unit> <regex> : 0 if a live proc matching <regex> exists in the unit's cgroup
bridge_up() {
  local svc="$1" rx="$2" cgfile="$CG_BASE/$1/cgroup.procs" pid cmd
  [[ -r "$cgfile" ]] || return 1
  while read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    [[ "$cmd" =~ $rx ]] && return 0
  done < "$cgfile"
  return 1
}

restart_node() {
  local name="$1" svc="$2" rx="$3" reason="$4"
  log_journal "🔴 watchdog: ${name} ${reason} — restarting ${svc}"
  if systemctl --user restart "$svc" 2>>"$HEARTBEAT"; then
    # bridge can take a few seconds to spawn — poll up to ~20s instead of one fixed sleep
    local i
    for i in $(seq 1 10); do
      sleep 2
      if systemctl --user is-active --quiet "$svc" && bridge_up "$svc" "$rx"; then
        log_journal "✅ watchdog: ${name} restarted, bridge back up"
        return 0
      fi
    done
    log_journal "❌ watchdog: ${name} restart did NOT restore bridge — manual check needed"
  else
    log_journal "❌ watchdog: ${name} systemctl restart FAILED"
  fi
}

for entry in "${NODES[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  svc="${rest%%|*}"
  rx="${rest##*|}"

  # skip nodes that aren't installed on this host (fleet portability)
  systemctl --user list-unit-files "$svc" --no-legend 2>/dev/null | grep -q . || continue

  if ! systemctl --user is-active --quiet "$svc"; then
    restart_node "$name" "$svc" "$rx" "service DOWN"
    continue
  fi

  if ! bridge_up "$svc" "$rx"; then
    [[ "$rx" == *telegram* ]] && t=Telegram || t=Discord
    restart_node "$name" "$svc" "$rx" "alive but ${t} bridge DEAD"
    continue
  fi

  log_beat "✅ ${name} healthy (service active + bridge up)"
done
