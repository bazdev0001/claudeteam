#!/bin/bash
# Push local decisions to GitHub (called by agents every ~1 min)
# Usage: decisions-push.sh <agent-type> [local-decisions-file]

set -euo pipefail

AGENT_TYPE=${1:-claude}
LOCAL_DECISIONS=${2:-}
GITHUB_PATH="/home/barry/projects/agents/${AGENT_TYPE}/decisions.md"

if [ -z "$LOCAL_DECISIONS" ] || [ ! -f "$LOCAL_DECISIONS" ]; then
  echo "No local decisions to sync"
  exit 0
fi

# Append new decisions to GitHub version (avoid overwrites)
if [ ! -f "$GITHUB_PATH" ]; then
  cp "$LOCAL_DECISIONS" "$GITHUB_PATH"
else
  # Append only new decisions (those with today's date)
  grep "^- \*\*D" "$LOCAL_DECISIONS" 2>/dev/null | while read line; do
    grep -q "$line" "$GITHUB_PATH" || echo "$line" >> "$GITHUB_PATH"
  done
fi

# Git commit if changes exist
cd /home/barry/projects/agents
if git diff --quiet $GITHUB_PATH; then
  exit 0
fi

git add $GITHUB_PATH
git commit -m "decisions: $AGENT_TYPE appends decision(s)" 2>/dev/null || true
git push origin main 2>/dev/null || echo "⚠️  Git push failed (may be offline)"

echo "✅ Decisions synced to GitHub"
