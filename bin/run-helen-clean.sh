#!/usr/bin/env bash
# Clean-room clone of Sage/tc2's run-channel-service-tc2.sh, adapted for Helen.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export CLAUDE_CHANNEL_HOST="vps"
export FLEET_NODE="vps-helen"
export TELEGRAM_STATE_DIR="$HOME/.claude/channels/telegram-helen"
cd "$HOME/helen-home" || exit 1
exec script -qfc "$HOME/bin/_helen-clean-exec.sh" /dev/null
