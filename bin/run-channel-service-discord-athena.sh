#!/usr/bin/env bash
# Service entrypoint for Athena's Discord presence.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.hermes/node/bin:$PATH"
export CLAUDE_CHANNEL_HOST="minipc"
export FLEET_NODE="minipc-discord-athena"
export DISCORD_STATE_DIR="$HOME/apex/agents/athena/discord"
cd "$HOME/projects/claudeteam" || exit 1
# `script` provides the pty; claude --channels needs a TTY or it drops to --print mode.
exec script -qfc "$HOME/projects/claudeteam/bin/_channel-exec-discord-athena.sh" /dev/null
