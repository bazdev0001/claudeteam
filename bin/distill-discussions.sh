#!/usr/bin/env bash
# Extract key decisions/agreements from today's raw discussion log and add to central summary.
# Runs daily at midnight via systemd timer.

set -euo pipefail

OBSIDIAN="/home/barry/projects/obsidian"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d yesterday +%Y-%m-%d)

# Raw log (yesterday's discussions — we distill them after the day ends)
RAW_LOG="$OBSIDIAN/minipc/discussions/$YESTERDAY.md"
CENTRAL="$OBSIDIAN/discussion.md"

# Ensure central file exists
touch "$CENTRAL"

# If no raw log from yesterday, nothing to distill
[ ! -f "$RAW_LOG" ] && exit 0

# Extract lines marked with **Agreement:**, **Decision:**, **Incident:**
# Format: grep for these markers and extract until next section
{
  echo ""
  echo "## $YESTERDAY — Mini PC"
  grep -E "^\*\*(Agreement|Decision|Incident|Gotcha):" "$RAW_LOG" | sed 's/^\*\*/- **/' || true
  echo ""
} >> "$CENTRAL"

cd "$OBSIDIAN" || exit 1
git add discussion.md minipc/discussions/ 2>/dev/null || true
git commit -m "distill: discussions from $YESTERDAY" 2>/dev/null || true
git push 2>/dev/null || true
