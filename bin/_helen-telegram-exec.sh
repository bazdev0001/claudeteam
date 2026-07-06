#!/usr/bin/env bash
# Aligned to Sage/tc2 (2026-07-04). Key parity fixes:
#  - export BAZMENT_AGENT so the SessionStart hook injects fleet context instead of fataling
#  - NO raw `tail -100 journal` append (it bloated the prompt AND embedded process names
#    like "bun server.ts" that poisoned every process-grep health check). Fleet context now
#    comes cleanly from the SessionStart hook; per-session continuity from helen-handoff.md.
#  - model matches Sage (claude-fable-5)
set -euo pipefail
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
export BAZMENT_AGENT="helen"
export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram-helen}"
mkdir -p "$TELEGRAM_STATE_DIR" "$HOME/.cache"
TZ="America/Los_Angeles" date "+%Y-%m-%d %H:%M:%S PDT Memory download" >> "$HOME/.cache/helen-session-start.log"

SOUL="$HOME/.claude/helen-soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")

HANDOFF="$HOME/bazment/obsidian/helen-handoff.md"
if [ -f "$HANDOFF" ]; then
  ARGS+=(--append-system-prompt "$(printf "\n\n## CONTEXT FROM PREVIOUS SESSION\n"; cat "$HANDOFF")")
fi

exec claude --dangerously-skip-permissions \
  --model claude-fable-5 \
  --channels plugin:telegram@claude-plugins-official \
  "${ARGS[@]}"
