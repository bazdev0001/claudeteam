#!/usr/bin/env bash
# Service entrypoint: run the always-on Telegram Claude session under a pseudo-terminal
# (claude --channels needs a TTY or it drops to --print mode). Supervised by systemd.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.hermes/node/bin:$PATH"
export CLAUDE_CHANNEL_HOST="minipc"
# Isolated telegram plugin state (separate inbox/access/bot.pid), mirroring tc2's pattern —
# the default shared dir let every interactive session's bridge SIGTERM this one via bot.pid.
export TELEGRAM_STATE_DIR="$HOME/apex/agents/athena/telegram"
cd "$HOME/projects/claudeteam" || exit 1
# `script` provides the pty; claude serves Telegram and never reads real stdin.
# The actual claude invocation (incl. --dangerously-skip-permissions and the node-local
# soul) lives in _channel-exec.sh so the soul can be passed as a real argv array.
exec script -qfc "$HOME/projects/claudeteam/bin/_channel-exec.sh" /dev/null
