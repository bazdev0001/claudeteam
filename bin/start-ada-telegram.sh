#!/usr/bin/env bash
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram}"
cd "$HOME/bazment-telegram"
exec script -qfc "/home/apex/bin/_ada-telegram-exec.sh" /dev/null
