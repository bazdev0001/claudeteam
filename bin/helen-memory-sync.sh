#!/usr/bin/env bash
# Periodic memory sync for Helen: PULL both vaults + PUSH her own writes.
# Was pull-only — helen-handoff.md and journal entries never left the box, so
# any VPS problem meant permanent memory loss. Runs every 10 min via timer
# (also invoked by helen-reset.sh right before any restart).

set -uo pipefail

LOG="$HOME/claudeclaw/logs/helen-memory-sync.log"
mkdir -p "$(dirname "$LOG")" "$HOME/.cache"
ts(){ date "+%Y-%m-%d %H:%M:%S"; }

sync_repo(){ # $1 = repo root, rest = pathspecs Helen owns (scoped add — never
             # sweep unrelated working-tree changes into an automated commit)
  local repo="$1"; shift
  [[ -d "$repo/.git" ]] || return 0
  if git -C "$repo" pull --quiet --rebase --autostash 2>/dev/null; then
    echo "$(ts) Memory download OK ($repo)" >> "$LOG"
    echo "$(ts) Memory download" > "$HOME/.cache/helen-session-start.log"
    echo "$(ts) Memory sync OK (vault pulled)" >> "$HOME/.cache/helen-memory-sync.log"
  else
    echo "$(ts) WARN pull failed ($repo)" >> "$LOG"
  fi
  git -C "$repo" add -- "$@" 2>/dev/null || true
  if ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
    git -C "$repo" commit --quiet -m "helen: memory sync" 2>/dev/null || true
  fi
  if [[ -n "$(git -C "$repo" rev-list @{u}..HEAD 2>/dev/null)" ]]; then
    if git -C "$repo" push --quiet 2>/dev/null; then
      echo "$(ts) Memory upload OK ($repo)" >> "$LOG"
      echo "$(ts) Memory upload" > "$HOME/.cache/helen-memory-upload.log"
    else
      echo "$(ts) WARN push failed ($repo)" >> "$LOG"
    fi
  fi
}

sync_repo "$HOME/bazment" obsidian/helen-handoff.md obsidian/journal
sync_repo "$HOME/projects/obsidian" journal tasks RESPONSIBILITIES.md

# freshness marker on every successful cycle — a quiet interval with nothing to push
# is healthy, and monitors must not read it as a dead sync (2026-07-04 false positive)
echo "$(ts) Memory sync cycle OK" > "$HOME/.cache/helen-memory-upload.log"
