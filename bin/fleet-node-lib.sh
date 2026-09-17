#!/usr/bin/env bash
# fleet-node-lib.sh — shared helpers for per-node fleet health checks on the mini-PC.
# Source this; do not execute it.
#
# WHY THIS EXISTS (2026-09-15, ISS-009 follow-up):
# Two separate silent-death bugs made the older health scripts no-ops for weeks:
#   1. They looked for a bot token in `~/apex/agents/<node>/telegram/.env` — a file that does
#      not exist on this host. The token actually lives in the channel service unit's
#      `Environment=`. Every lookup fell through and the scripts exited 0 without a word.
#   2. The per-node stamps (`~/.cache/tc2-last-inbound` / `-last-reply`) are written by hooks
#      in the SHARED `~/.claude/settings.json`, which BOTH Sage and Athena load. Whichever
#      node received a message stamped the tc2 files, so Athena's traffic looked like Sage's
#      and vice versa. Any watcher built on those stamps would mis-fire on the wrong node.
# Both are fixed here: token comes from the unit, stamps are keyed by TELEGRAM_STATE_DIR.
#
# NEVER write a token into a file under ~/projects/obsidian — that vault syncs to GitHub.

FLEET_CACHE="${FLEET_CACHE:-$HOME/.cache/fleet}"
FLEET_LOG="${FLEET_LOG:-$HOME/logs/fleet-health.log}"
FLEET_CHAT_ID="${FLEET_CHAT_ID:-6062064959}"   # Barry; matches allowFrom in both access.json

# node | systemd unit | telegram state dir (the per-node discriminator visible in proc env)
FLEET_NODES=(
  "sage|claudeteam-channel-tc2.service|/home/barry/apex/agents/sage/telegram"
  "athena|claudeteam-channel.service|/home/barry/apex/agents/athena/telegram"
)

fleet_log() {
  mkdir -p "$(dirname "$FLEET_LOG")" 2>/dev/null
  echo "$(TZ=America/Los_Angeles date '+%F %T %Z') $*" >> "$FLEET_LOG"
}

fleet_node_unit()  { local n; for e in "${FLEET_NODES[@]}"; do n="${e%%|*}"; [[ "$n" == "$1" ]] && { e="${e#*|}"; echo "${e%%|*}"; return 0; }; done; return 1; }
fleet_node_state() { local n; for e in "${FLEET_NODES[@]}"; do n="${e%%|*}"; [[ "$n" == "$1" ]] && { echo "${e##*|}"; return 0; }; done; return 1; }

# fleet_node_for_statedir <dir> : map a TELEGRAM_STATE_DIR back to a node name.
# Used by the hook stamper so each session writes only its OWN stamps.
fleet_node_for_statedir() {
  local d="${1%/}" n s
  for e in "${FLEET_NODES[@]}"; do
    n="${e%%|*}"; s="${e##*|}"
    [[ "${s%/}" == "$d" ]] && { echo "$n"; return 0; }
  done
  return 1
}

# fleet_node_token <node> : read TELEGRAM_BOT_TOKEN out of the node's live unit Environment=.
# Works from a timer context (which inherits nothing from the channel session). Prints the
# token on stdout; never logs it.
fleet_node_token() {
  local unit env_blob
  unit=$(fleet_node_unit "$1") || return 1
  env_blob=$(systemctl --user show "$unit" --property=Environment --value 2>/dev/null) || return 1
  [[ -n "$env_blob" ]] || return 1
  # Environment= is a space-separated KEY=VAL list; the token has no spaces.
  for kv in $env_blob; do
    [[ "$kv" == TELEGRAM_BOT_TOKEN=* ]] && { echo "${kv#TELEGRAM_BOT_TOKEN=}"; return 0; }
  done
  return 1
}

# fleet_alert <node> <text> : message Barry from that node's OWN bot, so the alert appears in
# the same chat the node normally speaks in. Returns non-zero if it could not send, so callers
# can log the failure instead of assuming Barry was told.
fleet_alert() {
  local node="$1" text="$2" token http
  token=$(fleet_node_token "$node") || { fleet_log "[$node] ALERT-FAILED (no token in unit env): $text"; return 1; }
  http=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${FLEET_CHAT_ID}" \
    --data-urlencode "text=${text}" 2>/dev/null) || http=000
  if [[ "$http" == "200" ]]; then
    fleet_log "[$node] alert sent: $text"
    return 0
  fi
  fleet_log "[$node] ALERT-FAILED (telegram http=$http): $text"
  return 1
}

# fleet_stamp_dir <node> : per-node stamp dir, created on demand.
fleet_stamp_dir() { local d="$FLEET_CACHE/$1"; mkdir -p "$d" 2>/dev/null; echo "$d"; }

# fleet_mtime <file> : mtime epoch, or 0 when absent.
fleet_mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
