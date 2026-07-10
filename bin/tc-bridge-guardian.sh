#!/usr/bin/env bash
# tc-bridge-guardian — fast (5s) replacement for the 3-min tc-healthcheck timer.
#
# Root problem: the Claude Code channel plugin spawns its transport BRIDGE (bun … telegram|discord)
# as a child of the `claude` process. When that bridge dies mid-session, `claude` keeps running, so
# the systemd service stays "active" and its Restart=always NEVER fires — the node goes deaf+mute
# but looks healthy. (This silenced Sage/tc2 on 2026-06-24.)
#
# This daemon closes the gap: it loops every 5s and, per always-on channel session, checks the
# service's OWN cgroup for the bridge IT must run. If the bridge is missing for MISS_THRESHOLD
# consecutive checks (so a normal ~4s restart gap is ignored), it `systemctl --user restart`s that
# service → fresh bridge in ~5-10s instead of the old ≤3 min.
#
# Why a loop daemon and not in-process: the bridge isn't ours to wrap (claude spawns it), so we
# never touch the launch path — this can't take the bots down. systemd keeps THIS daemon alive via
# Restart=always (who watches the watcher = systemd).
#
# Detection reads cgroup.procs + /proc/*/cmdline directly (immune to `systemctl status` truncation
# and the huge --append-system-prompt cmdlines). NOT telegram-specific: covers Discord too.

set -uo pipefail   # NOT -e: one node's failure must never abort the loop for the others

CG_BASE="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice"
HEARTBEAT="/tmp/tc-watchdog.log"
INTERVAL=5             # seconds between sweeps
MISS_THRESHOLD=2       # consecutive misses before acting (~10s) -> ignores normal restart gaps
COOLDOWN_LOOPS=48      # sweeps to skip a node right after we restart it (240s — at WSL2 boot all 4 sessions start simultaneously; 120s was too tight)

# node label | systemd unit | bridge cmdline regex it MUST be running
NODES=(
  "tc1(Athena/telegram)|claudeteam-channel.service|bun run.*telegram"
  "tc2(Sage/telegram)|claudeteam-channel-tc2.service|bun run.*telegram"
  "tc2(Sage/discord)|claudeteam-channel-discord.service|bun run.*discord"
  "tc1(Athena/discord)|claudeteam-channel-discord-athena.service|bun run.*discord"
)

log_journal() { echo "[$(date +%H:%M:%S)] $*" >> "/home/barry/projects/obsidian/journal/$(date +%Y-%m-%d).md"; }
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

declare -A MISS COOLDOWN INSTALLED
for entry in "${NODES[@]}"; do
  svc="${entry#*|}"; svc="${svc%%|*}"
  MISS["$svc"]=0; COOLDOWN["$svc"]=0
  if systemctl --user list-unit-files "$svc" --no-legend 2>/dev/null | grep -q .; then
    INSTALLED["$svc"]=1
  else
    INSTALLED["$svc"]=0
  fi
done

log_journal "🛡️ bridge-guardian started (sweep ${INTERVAL}s, act after ${MISS_THRESHOLD} misses) — watching telegram+discord nodes"

while true; do
  for entry in "${NODES[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    svc="${rest%%|*}"
    rx="${rest##*|}"

    [[ "${INSTALLED[$svc]}" == "1" ]] || continue

    if (( COOLDOWN[$svc] > 0 )); then
      COOLDOWN[$svc]=$(( COOLDOWN[$svc] - 1 ))
      continue
    fi

    [[ "$rx" == *telegram* ]] && t=Telegram || t=Discord

    if ! systemctl --user is-active --quiet "$svc"; then
      (( MISS[$svc]++ ))
      if (( MISS[$svc] >= MISS_THRESHOLD )); then
        log_journal "🔴 guardian: ${name} service DOWN — restarting ${svc}"
        systemctl --user restart "$svc" 2>>"$HEARTBEAT" \
          && log_journal "✅ guardian: ${name} restarted (service was down)"
        MISS[$svc]=0; COOLDOWN[$svc]=$COOLDOWN_LOOPS
      fi
      continue
    fi

    if bridge_up "$svc" "$rx"; then
      MISS[$svc]=0
      continue
    fi

    # service active but bridge missing.
    # Boot grace: a session restarted outside this loop (reset timer, manual) has no
    # cooldown here — without this check we'd kill it mid-boot before the bridge spawns.
    enter_s=$(date -d "$(systemctl --user show "$svc" --property=ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
    if (( $(date +%s) - enter_s < 240 )); then MISS[$svc]=0; continue; fi
    (( MISS[$svc]++ ))
    log_beat "⚠️ ${name} ${t} bridge missing (${MISS[$svc]}/${MISS_THRESHOLD})"
    if (( MISS[$svc] >= MISS_THRESHOLD )); then
      log_journal "🔴 guardian: ${name} alive but ${t} bridge DEAD — restarting ${svc}"
      if systemctl --user restart "$svc" 2>>"$HEARTBEAT"; then
        log_journal "✅ guardian: ${name} restarted (bridge was dead)"
      else
        log_journal "❌ guardian: ${name} systemctl restart FAILED"
      fi
      MISS[$svc]=0; COOLDOWN[$svc]=$COOLDOWN_LOOPS
    fi
  done
  sleep "$INTERVAL"
done
