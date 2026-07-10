#!/usr/bin/env bash
# Inner exec for the always-on Telegram session. Run via `script` (which supplies the pty).
# Kept separate from run-channel-service.sh so the soul can be passed as a real argv array —
# avoids any quoting/eval hazards from multi-line markdown (backticks, $, quotes).
set -euo pipefail

# Node-local personality ("soul"): lives OUTSIDE the synced claudeteam repo, so it is unique
# to THIS machine's Telegram bot and never reaches GitHub/VPS, other fleet members, or the
# ad-hoc Claude sessions started elsewhere on this PC. Skipped cleanly if absent.
SOUL="$HOME/.claude/claudeteam-channel-soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")

# Route through headroom proxy if running (context compression)
curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1 && export ANTHROPIC_BASE_URL=http://127.0.0.1:8787

exec claude --dangerously-skip-permissions \
  --model claude-sonnet-4-6 \
  --channels plugin:telegram@claude-plugins-official \
  "${ARGS[@]}"
