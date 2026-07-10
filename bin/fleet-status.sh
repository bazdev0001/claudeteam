#!/usr/bin/env bash
# fleet-status — ONE command for the TRUE health of every always-on channel node.
#
# Why this exists: `systemctl is-active` and `ps` LIE about channel nodes. The known
# upstream bug is the transport BRIDGE child (bun run … telegram|discord) dying while the
# `claude` parent stays alive — service shows "active" but the node is deaf+mute. Every past
# incident was first MISdiagnosed because of this. This check reads each service's cgroup for
# the bridge IT must run, so "healthy" here means "can actually send/receive", not "process exists".
#
# Usage: bash bin/fleet-status.sh   (or alias: fleet-status)
set -uo pipefail

CG_BASE="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice"

# label | systemd unit | bridge cmdline regex it MUST be running
NODES=(
  "Athena/telegram (tc1)|claudeteam-channel.service|bun run.*telegram"
  "Sage/telegram   (tc2)|claudeteam-channel-tc2.service|bun run.*telegram"
  "Sage/discord    (tc2)|claudeteam-channel-discord.service|bun run.*discord"
  "Athena/discord  (tc1)|claudeteam-channel-discord-athena.service|bun run.*discord"
)

bridge_up() {
  local cgfile="$CG_BASE/$1/cgroup.procs" rx="$2" pid cmd
  [[ -r "$cgfile" ]] || return 1
  while read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    [[ "$cmd" =~ $rx ]] && return 0
  done < "$cgfile"
  return 1
}

printf "\n  FLEET STATUS  —  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf "  %-22s %-10s %-12s %s\n" "NODE" "SERVICE" "BRIDGE" "VERDICT"
printf "  %s\n" "────────────────────────────────────────────────────────────────"

all_ok=1
for entry in "${NODES[@]}"; do
  name="${entry%%|*}"; rest="${entry#*|}"; svc="${rest%%|*}"; rx="${rest##*|}"

  if ! systemctl --user list-unit-files "$svc" --no-legend 2>/dev/null | grep -q .; then
    printf "  %-22s %-10s %-12s %s\n" "$name" "—" "—" "⚪ not installed"
    continue
  fi

  svc_state=$(systemctl --user is-active "$svc" 2>/dev/null)
  if [[ "$svc_state" != "active" ]]; then
    printf "  %-22s %-10s %-12s %s\n" "$name" "$svc_state" "—" "🔴 SERVICE DOWN"
    all_ok=0; continue
  fi

  if bridge_up "$svc" "$rx"; then
    printf "  %-22s %-10s %-12s %s\n" "$name" "active" "up" "🟢 healthy"
  else
    printf "  %-22s %-10s %-12s %s\n" "$name" "active" "DEAD" "🔴 DEAF+MUTE (bridge died)"
    all_ok=0
  fi
done

# Guardian — the thing that auto-heals the above. If IT is down, nothing self-heals.
printf "  %s\n" "────────────────────────────────────────────────────────────────"
g_state=$(systemctl --user is-active tc-bridge-guardian.service 2>/dev/null)
if [[ "$g_state" == "active" ]]; then
  last=$(tail -1 /tmp/tc-watchdog.log 2>/dev/null | cut -c1-60)
  printf "  %-22s 🟢 active   (auto-heals dead bridges in ~5-10s)\n" "GUARDIAN"
  [[ -n "$last" ]] && printf "  %-22s last beat: %s\n" "" "$last"
else
  printf "  %-22s 🔴 %s  — NO AUTO-HEAL, nodes won't self-recover!\n" "GUARDIAN" "$g_state"
  all_ok=0
fi

printf "  %s\n" "────────────────────────────────────────────────────────────────"
if [[ "$all_ok" == "1" ]]; then
  printf "  ✅ ALL NODES TRULY HEALTHY (service active + bridge live)\n\n"
else
  printf "  ⚠️  ISSUE ABOVE. A dead bridge self-heals in ~10s; wait then re-run.\n"
  printf "      Manual fix: systemctl --user restart <service>\n\n"
fi