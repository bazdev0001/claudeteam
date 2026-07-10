#!/usr/bin/env bash
# Modified start-channel.sh that injects status header instruction
cd "$(dirname "$0")/.." || exit 1
echo "==============================================================="
echo " Claude x Telegram  (project: $(pwd))"
echo " Bot: @Bazminipcclaude02bot"
echo " With: Automatic Status Header (restart time + latest updates)"
echo "==============================================================="

SOUL="$HOME/.claude/claudeteam-channel-soul.md"
SOUL_ARGS=()
[ -f "$SOUL" ] && SOUL_ARGS=(--append-system-prompt "$(cat "$SOUL")")

# Add status header instruction
STATUS_INSTRUCTION="
## CRITICAL: Status Header on Every Message
Before responding on Telegram, ALWAYS run and prepend:
\`\`\`bash
bash /home/barry/projects/claudeteam/bin/tc-status-header.sh
\`\`\`

This shows Barry:
1. When I came online (last restart time from /home/barry/projects/claudeteam/.state/tc-last-restart)
2. What was logged recently (decisions, tasks, updates from /home/barry/projects/obsidian/journal/)

Then your actual reply below the header. NO EXCEPTIONS.
"

SOUL_ARGS+=(--append-system-prompt "$STATUS_INSTRUCTION")

exec claude --channels plugin:telegram@claude-plugins-official "${SOUL_ARGS[@]}" "$@"
