#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$HOME/.claude/channels/discord-helen}"

mkdir -p "$DISCORD_STATE_DIR"

SOUL="$HOME/.claude/helen-soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")

exec claude --dangerously-skip-permissions \
  --model claude-sonnet-4-6 \
  --channels plugin:discord@claude-plugins-official \
  "${ARGS[@]}"
