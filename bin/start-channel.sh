#!/usr/bin/env bash
# Phase 1 launcher — start the Telegram-connected Claude Code session.
cd "$(dirname "$0")/.." || exit 1
echo "==============================================================="
echo " Claude x Telegram  (project: $(pwd))"
echo " Bot: @Bazminipcclaude02bot"
echo " With: Automatic Status Header (restart + latest updates)"
echo "==============================================================="

SOUL="$HOME/.claude/claudeteam-channel-soul.md"
SOUL_ARGS=()
[ -f "$SOUL" ] && SOUL_ARGS=(--append-system-prompt "$(cat "$SOUL")")

# Add status header instruction to every tc message
STATUS_INSTRUCTION="
## MANDATORY: Status Header on Every Telegram Reply
Before you send ANY message to Barry on Telegram, ALWAYS do this first:

1. Run: bash /home/barry/projects/claudeteam/bin/tc-status-header.sh
2. This outputs your status header showing:
   - When you came online (restart time)
   - Latest updates from the journal
3. Prepend that header to your reply
4. Then send your actual response

EXAMPLE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 tc online since: 2026-06-22 11:26:34
📋 Latest: tc Healthcheck deployed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[your actual reply here]

NO EXCEPTIONS. Every message, always.
"

SOUL_ARGS+=(--append-system-prompt "$STATUS_INSTRUCTION")

# Route through headroom proxy if running (context compression)
if curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
  export ANTHROPIC_BASE_URL=http://127.0.0.1:8787
fi

exec claude --channels plugin:telegram@claude-plugins-official "${SOUL_ARGS[@]}" "$@"
