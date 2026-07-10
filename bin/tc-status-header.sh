#!/usr/bin/env bash
# Generate tc status header showing restart time + latest updates
# Usage: bash tc-status-header.sh

RESTART_FILE="/home/barry/projects/claudeteam/.state/tc-last-restart"
JOURNAL="/home/barry/projects/obsidian/journal/$(date +%Y-%m-%d).md"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "$RESTART_FILE" ]; then
  RESTART_TIME=$(cat "$RESTART_FILE")
  echo "🤖 tc online since: $RESTART_TIME"
else
  echo "🤖 tc online"
fi

# Get latest logged event from journal (non-empty, non-timestamp lines)
if [ -f "$JOURNAL" ]; then
  LATEST_LOG=$(tac "$JOURNAL" | grep -v "^\[" | grep -v "^$" | head -3 | tac)
  if [ -n "$LATEST_LOG" ]; then
    echo "📋 Latest updates:"
    echo "$LATEST_LOG" | sed 's/^/   /'
  fi
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
