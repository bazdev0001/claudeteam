#!/usr/bin/env bash
# SessionStart hook for Ada (VPS): inject context from the SHARED fleet vault.
# Fleet vault lives at ~/bazment/obsidian/ (git clone of bazdev0001/obsidian).

FLEET_OBSIDIAN="$HOME/bazment/obsidian"

# Pull latest from shared vault (silent, best-effort)
if [ -d "$FLEET_OBSIDIAN/.git" ]; then
  git -C "$FLEET_OBSIDIAN" pull --quiet --rebase 2>/dev/null || true
fi

echo "=== ADA SESSION BRIEFING ==="
echo "Host: $(hostname) | User: $(whoami) | Time: $(date)"
echo "Ada = VPS Claude Code agent. Charlize/Hermes is OUT. No COO. Report directly to Barry."
echo "Domain: company ops, management coordination, VPS systems."
echo "Sibling: Sage (mini-PC, Discord/Telegram). Coordinate in #management channel."
echo ""

echo "=== FLEET VAULT CONTEXT ==="
if [ -f "$FLEET_OBSIDIAN/00-Briefing.md" ]; then
  echo "--- 00-Briefing.md ---"
  cat "$FLEET_OBSIDIAN/00-Briefing.md" | head -60
fi
echo ""

echo "=== LATEST JOURNAL ==="
latest=$(ls -1 "$FLEET_OBSIDIAN/journal/"*.md 2>/dev/null | sort | tail -1)
if [ -n "$latest" ]; then
  echo "($latest)"
  tail -n 60 "$latest"
else
  echo "No journal entries found."
fi
echo ""

echo "=== KEY DECISIONS (do not re-propose settled items) ==="
if [ -f "$FLEET_OBSIDIAN/DECISIONS.md" ]; then
  head -50 "$FLEET_OBSIDIAN/DECISIONS.md"
fi
echo ""

echo "=== END BRIEFING — log events to $FLEET_OBSIDIAN/journal/<YYYY-MM-DD>.md as you work ==="
