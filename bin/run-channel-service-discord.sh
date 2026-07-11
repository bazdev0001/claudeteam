#!/usr/bin/env bash
# Service entrypoint for the Discord node (Sage's Discord presence in the fleet Discord server).
# Mirrors the Telegram service but connects the discord plugin. Token lives in the state dir .env.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.hermes/node/bin:$PATH"
export CLAUDE_CHANNEL_HOST="minipc"
export FLEET_NODE="minipc-discord"
export DISCORD_STATE_DIR="$HOME/.claude/channels/discord-tc2"
cd "$HOME/projects/claudeteam" || exit 1
# `script` provides the pty; claude --channels needs a TTY or it drops to --print mode.
exec script -qfc "$HOME/projects/claudeteam/bin/_channel-exec-discord.sh" /dev/null
