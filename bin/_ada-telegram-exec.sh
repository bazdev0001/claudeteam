#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram}"

# Agent identity
export BAZMENT_AGENT="ada"
export BAZMENT_ROOT="${BAZMENT_ROOT:-$HOME/bazment}"
export OBSIDIAN_PATH="${OBSIDIAN_PATH:-$BAZMENT_ROOT/obsidian}"

# Ensure channel state dir exists
mkdir -p "$TELEGRAM_STATE_DIR"

# Ensure Telegram bot token is present in channel state .env
ENV_SRC="$HOME/claudeclaw/.env"
if [ -f "$ENV_SRC" ]; then
  TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_SRC" | cut -d= -f2-)
  [ -n "$TOKEN" ] && { echo "TELEGRAM_BOT_TOKEN=$TOKEN" > "$TELEGRAM_STATE_DIR/.env"; chmod 600 "$TELEGRAM_STATE_DIR/.env"; }
fi

# Ensure settings.json exists in BOTH the state dir and the canonical plugin dir.
# The plugin bridge reads from the canonical path (~/.claude/channels/telegram/settings.json)
# regardless of TELEGRAM_STATE_DIR; STATE_DIR controls inbox/pid/access only.
SETTINGS_CONTENT='{
  "enabledPlugins": {"telegram": true},
  "dmPolicy": "allowlist",
  "allowFrom": ["6062064959"],
  "groups": {},
  "pending": {},
  "mentionPatterns": []
}'
CANONICAL_DIR="$HOME/.claude/channels/telegram"
mkdir -p "$CANONICAL_DIR"
[ ! -f "$CANONICAL_DIR/settings.json" ] && echo "$SETTINGS_CONTENT" > "$CANONICAL_DIR/settings.json"
[ ! -f "$TELEGRAM_STATE_DIR/settings.json" ] && echo "$SETTINGS_CONTENT" > "$TELEGRAM_STATE_DIR/settings.json"

# Load soul: prefer maintained bazment agent soul, fallback to legacy file
SOUL="$BAZMENT_ROOT/agents/ada/soul.md"
ARGS=()
if [ -f "$SOUL" ]; then
  ARGS=(--append-system-prompt "$(cat "$SOUL")")
else
  SOUL2="$HOME/.claude/ada-discord-soul.md"
  [ -f "$SOUL2" ] && ARGS=(--append-system-prompt "$(cat "$SOUL2")")
fi

exec claude --dangerously-skip-permissions --model sonnet --channels plugin:telegram@claude-plugins-official "${ARGS[@]}"
