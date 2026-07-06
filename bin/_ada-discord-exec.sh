#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export BAZMENT_AGENT="ada"
export BAZMENT_ROOT="${BAZMENT_ROOT:-$HOME/bazment}"
export DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$BAZMENT_ROOT/channels/ada/discord}"
export OBSIDIAN_PATH="${OBSIDIAN_PATH:-$BAZMENT_ROOT/obsidian}"

# Ensure Discord bot token is present in channel state .env
ENV_SRC="$HOME/claudeclaw/.env"
if [ -f "$ENV_SRC" ]; then
  TOKEN=$(grep '^DISCORD_BOT_TOKEN=' "$ENV_SRC" | cut -d= -f2-)
  [ -n "$TOKEN" ] && { echo "DISCORD_BOT_TOKEN=$TOKEN" > "$DISCORD_STATE_DIR/.env"; chmod 600 "$DISCORD_STATE_DIR/.env"; }
fi

SOUL="$BAZMENT_ROOT/agents/ada/soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")
[ -z "${ARGS[*]}" ] && SOUL2="$HOME/.claude/ada-discord-soul.md" && [ -f "$SOUL2" ] && ARGS=(--append-system-prompt "$(cat "$SOUL2")")

exec script -qfc "claude --dangerously-skip-permissions --model sonnet --channels plugin:discord@claude-plugins-official $(printf '%q ' "${ARGS[@]}")" /dev/null
