#!/usr/bin/env bash
# Inner exec for tc2's always-on Telegram session. Run via `script` (supplies the pty).
# Separate from tc1's _channel-exec.sh so it loads tc2's OWN soul (software/general role).
set -euo pipefail

# Agent identity — required by agents-general-execution.sh (FATAL if unset)
export BAZMENT_AGENT="sage"

# Node-local personality ("soul") for tc2 — lives OUTSIDE the synced repo, unique to this node.
SOUL="$HOME/.claude/claudeteam-tc2-soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")

# Route through headroom proxy if running (context compression)
if curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
  export ANTHROPIC_BASE_URL=http://127.0.0.1:8787
fi

exec claude --dangerously-skip-permissions \
  --model claude-sonnet-4-6 \
  --channels plugin:telegram@claude-plugins-official \
  "${ARGS[@]}"
