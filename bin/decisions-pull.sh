#!/bin/bash
# Pull decisions from GitHub (called by agents every 5-10 min)
# Usage: decisions-pull.sh <agent-type> [output-file]

set -euo pipefail

AGENT_TYPE=${1:-claude}
OUTPUT_FILE=${2:-}
GITHUB_FLEET="/home/barry/projects/agents/decisions.md"
GITHUB_TYPE="/home/barry/projects/agents/${AGENT_TYPE}/decisions.md"

# Pull latest from GitHub
cd /home/barry/projects/agents
git pull origin main 2>/dev/null || echo "⚠️  Git pull failed (may be offline)"

# Merge: fleet-wide + agent-type specifics
{
  echo "# Merged Decisions ($(date +%Y-%m-%d\ %H:%M:%S))"
  echo ""
  echo "## Fleet-Wide"
  grep -A 100 "^## Decided" "$GITHUB_FLEET" 2>/dev/null | head -20 || echo "(none)"
  echo ""
  echo "## ${AGENT_TYPE} Specific"
  grep -A 100 "^## Decided" "$GITHUB_TYPE" 2>/dev/null | head -20 || echo "(none)"
} > /tmp/decisions-merged.txt

if [ -n "$OUTPUT_FILE" ]; then
  cp /tmp/decisions-merged.txt "$OUTPUT_FILE"
  echo "✅ Decisions pulled and merged to $OUTPUT_FILE"
else
  cat /tmp/decisions-merged.txt
fi
