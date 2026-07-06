#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export BAZMENT_AGENT="sophia"
BAZMENT_ROOT="${BAZMENT_ROOT:-$HOME/bazment}"
export BAZMENT_ROOT
export DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$BAZMENT_ROOT/channels/sophia/discord}"
export OBSIDIAN_PATH="${OBSIDIAN_PATH:-$BAZMENT_ROOT/obsidian}"

SOUL="$BAZMENT_ROOT/agents/sophia/soul.md"
if [ ! -f "$SOUL" ]; then
  echo "FATAL: soul.md missing at $SOUL — agent cannot start without identity" >&2
  exit 1
fi
ARGS=(--append-system-prompt "$(cat "$SOUL")")

exec claude --dangerously-skip-permissions --model claude-opus-4-6 \
  --channels plugin:discord@claude-plugins-official "${ARGS[@]}"
