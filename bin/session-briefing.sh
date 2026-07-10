#!/usr/bin/env bash
# SessionStart hook: print a compact briefing so a fresh/reset session is caught up.
# Its stdout is injected into the new session's context.

# --- RULES MERGE: merge new-rules.md into rules.md, then clear new-rules.md ---
RULES="/home/barry/projects/claudeteam/rules.md"
NEW_RULES="/home/barry/projects/claudeteam/new-rules.md"
HEADER="# NEW-RULES — Live session rules (injected on every message, merged into rules.md on next startup)
# To add a rule: append it below this header line.
# This file is cleared back to this header after each merge."
if [ -f "$NEW_RULES" ]; then
  has_content=$(grep -v '^#' "$NEW_RULES" | grep -v '^[[:space:]]*$' | head -1)
  if [ -n "$has_content" ]; then
    echo "--- Merging new-rules.md into rules.md ---"
    {
      echo ""
      echo "## Rules added $(date +%Y-%m-%d) (merged from new-rules.md)"
      grep -v '^#' "$NEW_RULES" | grep -v '^[[:space:]]*$'
    } >> "$RULES"
    printf '%s\n' "$HEADER" > "$NEW_RULES"
    echo "--- Merge complete. new-rules.md cleared. ---"
  fi
fi

V="$HOME/projects/obsidian"
echo "=== DURABLE MEMORY BRIEFING ($V) ==="
[ -f "$V/00-Briefing.md" ] && cat "$V/00-Briefing.md"
echo

echo "=== LATEST JOURNAL ==="
latest=$(ls -1 "$V/journal"/*.md 2>/dev/null | sort | tail -1)
if [ -n "$latest" ]; then echo "($latest)"; tail -n 40 "$latest"; fi

echo
echo "=== DECISIONS ==="
[ -f "$V/DECISIONS.md" ] && cat "$V/DECISIONS.md"

echo
echo "=== CURRENT RULES ==="
[ -f "$RULES" ] && cat "$RULES" || echo "(no rules.md found)"

echo
echo "=== LEARNINGS ==="
[ -f "$V/notes/LEARNINGS.md" ] && cat "$V/notes/LEARNINGS.md"

echo
echo "=== FRICTION-LOG ==="
[ -f "$V/notes/FRICTION-LOG.md" ] && cat "$V/notes/FRICTION-LOG.md"

echo
echo "=== FLEET KNOWLEDGE ==="
[ -f "$V/knowledge.md" ] && cat "$V/knowledge.md"

echo
echo "=== AVAILABLE SKILLS ==="
[ -f "$V/notes/SKILLS.md" ] && cat "$V/notes/SKILLS.md"

echo
echo "=== OPEN TASKS ==="
if [ -d "$V/tasks" ]; then
  grep -rl "" "$V/tasks/" 2>/dev/null | while read f; do
    status=$(grep -i "^status:" "$f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
    echo "$status" | grep -qE "done|complete" && continue
    echo "  $(basename "$f"): $(grep -m1 "^#" "$f" 2>/dev/null || head -1 "$f")"
  done || true
fi
echo "(full files in $V/tasks/)"

echo
echo "=== ENVIRONMENT MAP ==="
cat <<ENV
Host:     $(hostname)
Vault:    $V
Scripts:  $HOME/projects/claudeteam/bin/
SSH VPS:  apex@srv1601002.hstgr.cloud (key: ~/.ssh/id_ed25519)
ENV

# --- SELF-IMPROVEMENT ENFORCEMENT ---
if [ -d "$V/self-improvement" ]; then
  echo
  echo "=== SELF-IMPROVEMENT (MANDATORY — fleet learning loop) ==="
  echo "You MUST participate in the self-improvement loop. Runbook: $V/self-improvement/README.md"
  echo "1. As you work, when Barry corrects or confirms you, append a signal to"
  echo "   $V/self-improvement/templates/signal-log.md (date | node | CORRECTION/CONFIRMATION | rule | confidence)."
  echo "2. BEFORE any context reset / shutdown, run $V/self-improvement/reflect-loop-prompt.md:"
  echo "   propose edits to your instruction files, score them with BINARY evals, present diffs to"
  echo "   Barry for approval, apply only approved+eval-passing changes, log them to the journal."
  echo "3. Shared learnings -> the vault; this node's personality/voice -> its PRIVATE files only."
  echo "=== END SELF-IMPROVEMENT ==="
fi

echo "=== END BRIEFING — append new events to $V/journal/$(date +%F).md as you work ==="
# marker so we can confirm the hook fired
mkdir -p "$HOME/.cache"; date "+%Y-%m-%d %H:%M:%S briefing-hook fired" >> "$HOME/.cache/claudeteam-briefing.log"
