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
#
# Zombie detection (added 2026-07-17 after Helen/VPS incident): a bridge can respawn "wedged" —
# process alive and matching the regex, but holding ZERO network connections → node deaf while
# looking healthy. The `bun run` wrapper we match never holds sockets itself; its child
# `bun server.ts` does (ESTAB :443). So the check maps wrapper→children via PPid inside the
# cgroup and requires ≥1 ESTAB tcp socket somewhere in that set, continuously absent for
# ZOMBIE_THRESHOLD sweeps before restarting. (Design ref: VPS helen-conn-watchdog v3.)

set -uo pipefail   # NOT -e: one node's failure must never abort the loop for the others

CG_BASE="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice"
HEARTBEAT="/tmp/tc-watchdog.log"
INTERVAL=5             # seconds between sweeps
MISS_THRESHOLD=2       # consecutive misses before acting (~10s) -> ignores normal restart gaps
COOLDOWN_LOOPS=48      # sweeps to skip a node right after we restart it (240s — at WSL2 boot all 4 sessions start simultaneously; 120s was too tight)
ZOMBIE_THRESHOLD=18    # consecutive sweeps with bridge alive but ZERO ESTAB tcp sockets (~90s) before restart — long enough to ride out telegram long-poll reconnect gaps

# node label | systemd unit | bridge cmdline regex it MUST be running
NODES=(
  "tc1(Athena/telegram)|claudeteam-channel.service|bun run.*telegram"
  "tc2(Sage/telegram)|claudeteam-channel-tc2.service|bun run.*telegram"
#  DISABLED 2026-09-02 (Barry: consistent crash-loop, remove for now — see ISS-009): "tc2(Sage/discord)|claudeteam-channel-discord-sage.service|bun run.*discord"
#  DISABLED 2026-09-02 (Barry: consistent crash-loop, remove for now — see ISS-009): "tc1(Athena/discord)|claudeteam-channel-discord-athena.service|bun run.*discord"
)

log_journal() { echo "[$(date +%H:%M:%S)] $*" >> "/home/barry/projects/obsidian/journal/$(date +%Y-%m-%d).md"; }
log_beat()    { echo "[$(date +%F\ %H:%M:%S)] $*" >> "$HEARTBEAT"; }
# Pre-restart context backup -> obsidian/journal/journal-new.md (merged+cleared on next startup)
backup_ctx()  { "$HOME/projects/claudeteam/bin/journal-new-backup.sh" "guardian: $1" >/dev/null 2>&1 || true; }

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

# bridge_estab <unit> <regex> : 0 if the matched bridge wrapper OR any of its direct children in the
# unit's cgroup holds ≥1 ESTAB tcp socket (per $estab_snap, one `ss -Htnp` per sweep). The regex
# matches the `bun run …` wrapper; the actual sockets live in its child `bun server.ts`, so we map
# wrapper→children via /proc/<pid>/status PPid. Conservative: any doubt (unreadable cgroup, no
# wrapper — that's bridge_up's job) → return 0, never accuse.
bridge_estab() {
  local svc="$1" rx="$2" cgfile="$CG_BASE/$1/cgroup.procs" pid cmd ppid w
  local -a wrappers=() cands=()
  [[ -r "$cgfile" ]] || return 0
  while read -r pid; do
    [[ -r "/proc/$pid/cmdline" ]] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    [[ "$cmd" =~ $rx ]] && wrappers+=("$pid")
  done < "$cgfile"
  (( ${#wrappers[@]} )) || return 0
  cands=("${wrappers[@]}")
  while read -r pid; do
    ppid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null)
    for w in "${wrappers[@]}"; do [[ "$ppid" == "$w" ]] && cands+=("$pid"); done
  done < "$cgfile"
  for pid in "${cands[@]}"; do
    [[ "$estab_snap" == *"pid=$pid,"* ]] && return 0
  done
  return 1
}

declare -A MISS COOLDOWN INSTALLED ZOMBIE
for entry in "${NODES[@]}"; do
  svc="${entry#*|}"; svc="${svc%%|*}"
  MISS["$svc"]=0; COOLDOWN["$svc"]=0; ZOMBIE["$svc"]=0
  if systemctl --user list-unit-files "$svc" --no-legend 2>/dev/null | grep -q .; then
    INSTALLED["$svc"]=1
  else
    INSTALLED["$svc"]=0
  fi
done

log_journal "🛡️ bridge-guardian started (sweep ${INTERVAL}s, act after ${MISS_THRESHOLD} misses) — watching telegram+discord nodes"

# --- Headroom proxy watchdog (added 2026-09-02, ISS-009) ---------------------------------------
# apex-headroom-proxy.service (127.0.0.1:8787) is Sage/Athena's ANTHROPIC_BASE_URL. When it's down,
# every API call for the session fails instantly with "Connection refused" — and nothing else
# signals it (service stays "active", claude proc stays alive). This was invisible for HOURS before
# (see ISS-009). Reuses this loop's existing 5s sweep + log_journal (fleet-alerter picks up the
# same ✅/🔴/❌ "guardian:" lines automatically — no changes needed there).
HR_SVC="apex-headroom-proxy.service"
HR_URL="http://127.0.0.1:8787/readyz"
HR_NAME="shared(Headroom/proxy)"
HR_MISS=0
HR_COOLDOWN=0

while true; do
  # One ESTAB snapshot per sweep, shared by all nodes' zombie checks. Empty snapshot (ss failed
  # or literally zero ESTAB machine-wide) → zombie checks skip this sweep rather than mass-strike.
  estab_snap=$(ss -Htnp state established 2>/dev/null)
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
        backup_ctx "${svc} was down"
        systemctl --user restart "$svc" 2>>"$HEARTBEAT" \
          && log_journal "✅ guardian: ${name} restarted (service was down)"
        MISS[$svc]=0; COOLDOWN[$svc]=$COOLDOWN_LOOPS
      fi
      continue
    fi

    if bridge_up "$svc" "$rx"; then
      MISS[$svc]=0
      # Zombie check: bridge proc exists but its process tree holds ZERO ESTAB tcp sockets —
      # respawned "wedged" (Helen/VPS 2026-07-17): matches regex, looks healthy, node is deaf.
      if [[ -z "$estab_snap" ]] || bridge_estab "$svc" "$rx"; then
        ZOMBIE[$svc]=0
        continue
      fi
      # Same boot grace as the miss path: a fresh session may not have connected yet.
      enter_s=$(date -d "$(systemctl --user show "$svc" --property=ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
      if (( $(date +%s) - enter_s < 240 )); then ZOMBIE[$svc]=0; continue; fi
      (( ZOMBIE[$svc]++ ))
      log_beat "🧟 ${name} ${t} bridge alive but no ESTAB (${ZOMBIE[$svc]}/${ZOMBIE_THRESHOLD})"
      if (( ZOMBIE[$svc] >= ZOMBIE_THRESHOLD )); then
        log_journal "🔴 guardian: ${name} zombie bridge: alive but no ESTAB for $(( ZOMBIE[$svc] * INTERVAL ))s — restarting ${svc}"
        backup_ctx "${svc} zombie bridge (no ESTAB)"
        if systemctl --user restart "$svc" 2>>"$HEARTBEAT"; then
          log_journal "✅ guardian: ${name} restarted (zombie bridge)"
        else
          log_journal "❌ guardian: ${name} systemctl restart FAILED (zombie)"
        fi
        ZOMBIE[$svc]=0; MISS[$svc]=0; COOLDOWN[$svc]=$COOLDOWN_LOOPS
      fi
      continue
    fi
    ZOMBIE[$svc]=0   # bridge gone entirely -> miss path owns it; new bridge gets a fresh zombie count

    # service active but bridge missing.
    # Boot grace: a session restarted outside this loop (reset timer, manual) has no
    # cooldown here — without this check we'd kill it mid-boot before the bridge spawns.
    enter_s=$(date -d "$(systemctl --user show "$svc" --property=ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
    if (( $(date +%s) - enter_s < 240 )); then MISS[$svc]=0; continue; fi
    (( MISS[$svc]++ ))
    log_beat "⚠️ ${name} ${t} bridge missing (${MISS[$svc]}/${MISS_THRESHOLD})"
    if (( MISS[$svc] >= MISS_THRESHOLD )); then
      log_journal "🔴 guardian: ${name} alive but ${t} bridge DEAD — restarting ${svc}"
      backup_ctx "${svc} bridge dead"
      if systemctl --user restart "$svc" 2>>"$HEARTBEAT"; then
        log_journal "✅ guardian: ${name} restarted (bridge was dead)"
      else
        log_journal "❌ guardian: ${name} systemctl restart FAILED"
      fi
      MISS[$svc]=0; COOLDOWN[$svc]=$COOLDOWN_LOOPS
    fi
  done

  # Headroom proxy check (separate from the NODES loop — HTTP health, not a bridge-in-cgroup check)
  if (( HR_COOLDOWN > 0 )); then
    (( HR_COOLDOWN-- ))
  elif curl -sf --max-time 2 "$HR_URL" >/dev/null 2>&1; then
    HR_MISS=0
  else
    (( HR_MISS++ ))
    log_beat "⚠️ ${HR_NAME} not ready (${HR_MISS}/${MISS_THRESHOLD})"
    if (( HR_MISS >= MISS_THRESHOLD )); then
      log_journal "🔴 guardian: ${HR_NAME} not responding — restarting ${HR_SVC}"
      if systemctl --user restart "$HR_SVC" 2>>"$HEARTBEAT"; then
        log_journal "✅ guardian: ${HR_NAME} restarted (service was down)"
      else
        log_journal "❌ guardian: ${HR_NAME} systemctl restart FAILED"
      fi
      HR_MISS=0; HR_COOLDOWN=$COOLDOWN_LOOPS
    fi
  fi

  sleep "$INTERVAL"
done
