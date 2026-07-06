#!/usr/bin/env bash
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export BAZMENT_AGENT="ada"
export BAZMENT_ROOT="${BAZMENT_ROOT:-$HOME/bazment}"
export DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$BAZMENT_ROOT/channels/ada/discord}"
mkdir -p "$HOME/bazment/logs"
cd "$HOME/claudeclaw"
# Auto-dismiss "Try fullscreen renderer?" dialog, then keep stdin open
{ sleep 2; printf '\r'; sleep infinity; } | exec /home/apex/bin/_ada-discord-exec.sh
