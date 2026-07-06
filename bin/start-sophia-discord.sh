#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export BAZMENT_AGENT="sophia"
export BAZMENT_ROOT="${BAZMENT_ROOT:-$HOME/bazment}"
export DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$BAZMENT_ROOT/channels/sophia/discord}"
mkdir -p "$BAZMENT_ROOT/logs"
cd "$HOME/claudeclaw" || exit 1
{ sleep 2; printf "\r"; sleep infinity; } | exec script -qfc "$HOME/bin/_sophia-discord-exec.sh" "$BAZMENT_ROOT/logs/sophia-discord.log"
