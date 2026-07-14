#!/usr/bin/env bash
# Service entrypoint for tc2 (software/general node). Mirrors run-channel-service.sh but with
# an ISOLATED Telegram state dir + its own bot token, so it never collides with tc1's inbox.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.hermes/node/bin:$PATH"
export CLAUDE_CHANNEL_HOST="minipc"
export FLEET_NODE="minipc-tc2"
# Isolated telegram plugin state (separate inbox/access/.env/bot.pid). Token lives in its .env.
export TELEGRAM_STATE_DIR="$HOME/apex/agents/sage/telegram"
cd "$HOME/projects/claudeteam" || exit 1
# `script` provides the pty; claude --channels needs a TTY or it drops to --print mode.
exec script -qfc "$HOME/projects/claudeteam/bin/_channel-exec-tc2.sh" /dev/null
