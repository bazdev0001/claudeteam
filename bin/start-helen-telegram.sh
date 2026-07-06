#!/usr/bin/env bash
# Aligned to Sage/tc2 proven launcher (2026-07-04): clean `exec script` with NO
# stdin pipe. The old `{ sleep 2; printf \r; sleep infinity; } |` fed a held-open
# pipe into script and correlated with a flapping bridge<->session MCP link that
# silently dropped inbound messages.
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export CLAUDE_CHANNEL_HOST="vps"
export FLEET_NODE="vps-helen"
export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram-helen}"
mkdir -p "$TELEGRAM_STATE_DIR"
cd "$HOME/helen-tg" || exit 1
exec script -qfc "$HOME/bin/_helen-telegram-exec.sh" /dev/null
