#!/usr/bin/env bash
# fleet-push-verify.sh — catch "committed but never reached GitHub" before it sits for months.
#
# WHY (ISS-004): Sage committed a CLAUDE.md refactor on 2026-06-30 and both pushes failed.
# Nothing alerted, so it sat broken until 2026-09-15 — root cause turned out to be a dead
# GitHub token embedded in the claudeteam remote URL, and the SAME dead token was in 17 other
# repos, all silently unable to push. A push that fails is invisible: the commit exists
# locally, `git log` looks right, and the work simply never leaves the machine.
#
# HOW: two passes, cheap first.
#  1. No-network: `git rev-list --count @{upstream}..HEAD`. The upstream tracking ref only
#     moves on a successful fetch/push, so unpushed commits show up without touching the
#     network. Fast enough to run over every repo every time.
#  2. Network confirm, ONLY for repos flagged in pass 1 and only if they've been behind longer
#     than GRACE (a commit made 2 minutes ago is not a failure — it just hasn't been pushed
#     yet). Bounded by `timeout` so a hung remote can't stall the whole sweep, which is what
#     made the ad-hoc version of this check time out at 2 minutes.
#
# Alerts Barry once per day per repo, from Sage's bot. DRY_RUN=1 to test.

set -uo pipefail

LIB="$HOME/projects/claudeteam/bin/fleet-node-lib.sh"
# shellcheck disable=SC1090
. "$LIB" || { echo "fleet-push-verify: cannot source $LIB" >&2; exit 1; }

SCAN_ROOTS="${SCAN_ROOTS:-$HOME/projects $HOME/apex}"
GRACE="${GRACE:-3600}"            # ignore repos whose newest commit is younger than 1h
FETCH_TIMEOUT="${FETCH_TIMEOUT:-15}"
MAX_CONFIRM="${MAX_CONFIRM:-10}"  # cap network confirms per sweep
DRY_RUN="${DRY_RUN:-0}"
STATE="$FLEET_CACHE/push-verify"
mkdir -p "$STATE" 2>/dev/null

now=$(date +%s)
declare -a flagged=()

# ---- pass 1: no network ----
while IFS= read -r gitdir; do
  repo=$(dirname "$gitdir")
  branch=$(git -C "$repo" branch --show-current 2>/dev/null) || continue
  [ -n "$branch" ] || continue
  # No upstream configured => nothing to verify against; not a failure.
  git -C "$repo" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1 || continue
  n=$(git -C "$repo" rev-list --count '@{upstream}..HEAD' 2>/dev/null) || continue
  [ "${n:-0}" -gt 0 ] || continue
  last=$(git -C "$repo" log -1 --format=%ct HEAD 2>/dev/null || echo "$now")
  (( now - last < GRACE )) && continue     # freshly committed, give it time to be pushed
  flagged+=("$repo|$branch|$n|$last")
done < <(find $SCAN_ROOTS -maxdepth 2 -name .git -type d 2>/dev/null)

if (( ${#flagged[@]} == 0 )); then
  fleet_log "push-verify: OK — no repo has unpushed commits older than ${GRACE}s"
  exit 0
fi

# ---- pass 2: confirm over the network, bounded ----
declare -a stuck=()
count=0
for entry in "${flagged[@]}"; do
  repo="${entry%%|*}"; rest="${entry#*|}"
  branch="${rest%%|*}"; rest="${rest#*|}"
  n="${rest%%|*}"; last="${rest##*|}"
  name=$(basename "$repo")

  if (( count >= MAX_CONFIRM )); then
    fleet_log "push-verify: confirm cap reached (${MAX_CONFIRM}) — ${name} and any remainder not network-checked this sweep"
    break
  fi
  count=$((count+1))

  if ! timeout "$FETCH_TIMEOUT" git -C "$repo" fetch -q origin "$branch" 2>/dev/null; then
    stuck+=("$name [$branch]: cannot reach origin (fetch failed/timed out) — $n local commit(s) unpushed")
    continue
  fi
  n=$(git -C "$repo" rev-list --count "origin/$branch..$branch" 2>/dev/null || echo 0)
  (( n > 0 )) || continue
  age_h=$(( (now - last) / 3600 ))
  stuck+=("$name [$branch]: $n commit(s) unpushed, newest is ${age_h}h old")
done

if (( ${#stuck[@]} == 0 )); then
  fleet_log "push-verify: OK — all flagged repos confirmed in sync after fetch"
  exit 0
fi

msg="🔴 Work committed but NOT on GitHub (${#stuck[@]} repo(s)):"
for s in "${stuck[@]}"; do msg+=$'\n'"- $s"; done
msg+=$'\n'"Fix: cd into the repo and 'git push'. If auth fails, check 'git remote -v' — a dead token in the URL was the cause of ISS-004."

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN would alert:"; echo "$msg"; exit 0
fi

# One alert per repo per day.
today=$(TZ=America/Los_Angeles date +%F)
sig=$(printf '%s\n' "${stuck[@]}" | sed 's/:.*//' | sort | md5sum | cut -c1-12)
latch="$STATE/alerted-$sig"
if [[ "$(cat "$latch" 2>/dev/null)" == "$today" ]]; then
  fleet_log "push-verify: ${#stuck[@]} repo(s) stuck — alert suppressed (already sent today)"
  exit 1
fi

fleet_log "push-verify: ${#stuck[@]} repo(s) stuck: ${stuck[*]}"
if fleet_alert sage "$msg"; then echo "$today" > "$latch"; fi
exit 1
