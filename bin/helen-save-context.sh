#!/usr/bin/env bash
# Save Helen's session context before restart.
# Writes a handoff summary to obsidian that gets loaded by the next session.

set -euo pipefail

JOURNAL_DIR="/home/apex/bazment/obsidian/journal"
HANDOFF="/home/apex/bazment/obsidian/helen-handoff.md"
TODAY=$(date +%Y-%m-%d)
NOW=$(date '+%H:%M UTC')
JOURNAL="$JOURNAL_DIR/$TODAY.md"
JSONL_DIR="/home/apex/.claude/projects/-home-apex-claudeclaw"

mkdir -p "$JOURNAL_DIR"

# Extract last few conversation turns from the most recent JSONL
RECENT_CONVO=""
LATEST_JSONL=$(find "$JSONL_DIR" -maxdepth 1 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
  | sort -n | tail -1 | awk '{print $2}')

if [ -n "$LATEST_JSONL" ] && [ -f "$LATEST_JSONL" ]; then
  RECENT_CONVO=$(python3 -c "
import json, sys
lines = open('$LATEST_JSONL').readlines()
turns = []
for line in lines[-60:]:
    try:
        d = json.loads(line)
        role = d.get('message', {}).get('role', d.get('role', ''))
        content = d.get('message', {}).get('content', '')
        if isinstance(content, list):
            text = ' '.join(c.get('text','') for c in content if isinstance(c,dict) and c.get('type')=='text')
        elif isinstance(content, str):
            text = content
        else:
            continue
        if role in ('user','assistant') and text.strip():
            turns.append(f'{role.upper()}: {text.strip()[:200]}')
    except: pass
print('\n'.join(turns[-10:]))
" 2>/dev/null || echo "(could not parse conversation)")
fi

# Write handoff file for next session
{
  echo "# Helen Session Handoff — $TODAY $NOW"
  echo ""
  echo "## Last reset reason"
  echo "(triggered by smart reset — see journal for details)"
  echo ""
  echo "## Recent conversation context"
  echo '```'
  echo "${RECENT_CONVO:-no recent conversation extracted}"
  echo '```'
  echo ""
  echo "## Key active topics"
  echo "- Review the above conversation and continue from where we left off"
  echo "- Session was reset due to idle/age/context conditions — not a crash"
} > "$HANDOFF"

# Also append to daily journal
{
  echo ""
  echo "### $NOW — [Helen Reset] Session ended — context saved"
  echo "- Handoff written to helen-handoff.md"
  echo "- New session will load it on startup"
} >> "$JOURNAL"

# Commit and push to vault
cd "$HOME/bazment/obsidian"
git add journal/ helen-handoff.md 2>/dev/null || true
if git diff --cached --quiet; then
  echo "Nothing to commit"
else
  git commit -m "sync: helen session handoff $(date '+%Y-%m-%d %H:%M')" --quiet
  git push --quiet 2>/dev/null || echo "WARN: push failed"
fi

# Log upload timestamp
mkdir -p "$HOME/.cache"
date "+%Y-%m-%d %H:%M:%S" >> "$HOME/.cache/helen-memory-upload.log" 2>/dev/null || true

echo "Context saved to $JOURNAL and handoff written to $HANDOFF"
