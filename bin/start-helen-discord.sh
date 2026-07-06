#!/usr/bin/env bash
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$HOME/.claude/channels/discord-helen}"
mkdir -p "$DISCORD_STATE_DIR"
cd "$HOME/claudeclaw" || exit 1
{ sleep 2; printf "\r"; sleep infinity; } | exec script -qfc "/home/apex/bin/_helen-discord-exec.sh" /dev/null
