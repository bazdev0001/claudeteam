#!/usr/bin/env bash
# UserPromptSubmit hook: inject new-rules.md into context on every message.
# Only outputs if there's content beyond the header (comment/empty lines).
NEW_RULES="/home/barry/projects/claudeteam/new-rules.md"
[ -f "$NEW_RULES" ] || exit 0
# Check for any non-comment, non-empty lines
has_content=$(grep -v '^#' "$NEW_RULES" | grep -v '^[[:space:]]*$' | head -1)
if [ -n "$has_content" ]; then
  echo "=== LIVE SESSION RULES (new-rules.md) ==="
  cat "$NEW_RULES"
  echo "=== END LIVE SESSION RULES ==="
fi
