#!/usr/bin/env bash
# Inner exec for the Discord node. Run via `script` (supplies the pty).
set -euo pipefail

# Agent identity — required by agents-general-execution.sh (FATAL if unset)
export BAZMENT_AGENT="sage"

# Node-local soul for the Discord presence — lives OUTSIDE the synced repo.
SOUL="$HOME/.claude/claudeteam-discord-soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")

# Route through headroom proxy if running (context compression)
curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1 && export ANTHROPIC_BASE_URL=http://127.0.0.1:8787

exec claude --dangerously-skip-permissions \
  --model claude-sonnet-4-6 \
  --channels plugin:discord@claude-plugins-official \
  "${ARGS[@]}"
