#!/usr/bin/env bash
# nightly-journal-review.sh — 11:30pm PST daily (nightly-journal-review.timer).
# Barry's rule 2026-07-18: review ALL of today's journals, extract
#   (a) lessons learned  -> obsidian/self-improvement/lessons-learned.md (dated entry)
#   (b) new RULES        -> obsidian/agents/rules.md (global) + local rules.md + new-rules.md
# Uses a headless `claude -p` (same pattern as bin/daily-report.sh) with the ISS-007
# transient-claude safety: channel plugins disabled + scratch state dirs (see
# rules.md "Rules added 2026-07-17" and bin/claude-usage.py fetch()).
# Idempotent per day: marker file skips a second run the same date.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.hermes/node/bin:$PATH"

VAULT="$HOME/projects/obsidian"
PROJ="$HOME/projects/claudeteam"
TODAY=$(TZ=America/Los_Angeles date +%F)
LOG="$HOME/.cache/nightly-journal-review.log"
MARKER="$HOME/.cache/nightly-journal-review.last"
LESSONS="$VAULT/self-improvement/lessons-learned.md"
GLOBAL_RULES="$VAULT/agents/rules.md"
LOCAL_RULES="$PROJ/rules.md"
NEW_RULES="$PROJ/new-rules.md"
mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

# --- idempotence: one review per day ---
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$TODAY" ]; then
  log "SKIP already ran for $TODAY"
  exit 0
fi

# --- gather today's journal material ---
SOURCES=(
  "$VAULT/journal/$TODAY.md"
  "$VAULT/journal/journal-new.md"
  "$VAULT/minipc-tc2/discussions/$TODAY.md"
  "$VAULT/minipc/discussions/$TODAY.md"
  "$VAULT/minipc-discord/discussions/$TODAY.md"
)
TMP=$(mktemp /tmp/nightly-journal-review.XXXXXX)
trap 'rm -f "$TMP"' EXIT
for f in "${SOURCES[@]}"; do
  if [ -s "$f" ]; then
    { echo "===== SOURCE: ${f#$VAULT/} ====="; tail -c 60000 "$f"; echo; } >> "$TMP"
  fi
done
if [ ! -s "$TMP" ]; then
  log "NO journal content found for $TODAY — nothing to review"
  exit 0
fi
# context to avoid duplicating lessons already captured today (e.g. manual test run)
{ echo "===== LESSONS ALREADY RECORDED (do NOT repeat these) ====="
  awk "/^## $TODAY/,0" "$LESSONS" 2>/dev/null || true
  echo "===== EXISTING GLOBAL RULES (do NOT re-propose; headers only) ====="
  grep '^## ' "$GLOBAL_RULES" 2>/dev/null || true
} >> "$TMP"

PROMPT="You are the nightly journal reviewer for Barry's agent fleet (date: $TODAY, all times PST).
Stdin contains today's journal/discussion files, plus lessons already recorded today and existing rule headers.
Analyze the day and output EXACTLY this structure, nothing else (no preamble, no markdown fences):
===LESSONS===
- one bullet per lesson learned: what happened -> what we learned -> what we do differently. Concrete, short, operational. 0-6 bullets. If nothing new, output exactly: NONE
===RULES===
- one bullet per NEW permanent behavioral rule that Barry stated or that clearly emerged today and is NOT already in the existing rule headers. Rules are directives all agents must follow. Be conservative: only clear, durable rules. If none, output exactly: NONE"

# ISS-007 safety: transient claude must not touch live channel plugin state
SCRATCH="/tmp/nightly-journal-review-scratch"
mkdir -p "$SCRATCH/telegram" "$SCRATCH/discord"
NO_PLUGINS='{"enabledPlugins":{"telegram@claude-plugins-official":false,"discord@claude-plugins-official":false}}'

cd "$PROJ"
OUT=$(TELEGRAM_STATE_DIR="$SCRATCH/telegram" DISCORD_STATE_DIR="$SCRATCH/discord" \
      claude -p "$PROMPT" --dangerously-skip-permissions --settings "$NO_PLUGINS" \
      < "$TMP" 2>>"$LOG" || true)
if [ -z "${OUT// }" ] || ! grep -q '===LESSONS===' <<<"$OUT"; then
  log "ERROR claude returned empty/unparseable output; raw: ${OUT:0:300}"
  exit 1
fi

LESSONS_TXT=$(sed -n '/^===LESSONS===/,/^===RULES===/p' <<<"$OUT" | sed '1d;$d' | sed '/^[[:space:]]*$/d')
RULES_TXT=$(sed -n '/^===RULES===/,$p' <<<"$OUT" | sed '1d' | sed '/^[[:space:]]*$/d')

wrote=""
if [ -n "$LESSONS_TXT" ] && [ "$LESSONS_TXT" != "NONE" ]; then
  { echo; echo "## $TODAY — nightly journal review"; echo "$LESSONS_TXT"; } >> "$LESSONS"
  wrote="lessons($(grep -c '^-' <<<"$LESSONS_TXT"))"
fi
if [ -n "$RULES_TXT" ] && [ "$RULES_TXT" != "NONE" ]; then
  BLOCK="
## Rules added $TODAY (nightly journal review)
$RULES_TXT"
  echo "$BLOCK" >> "$GLOBAL_RULES"
  echo "$BLOCK" >> "$LOCAL_RULES"
  { echo "$BLOCK"; echo "(NOTE: already merged into local + global rules.md by nightly-journal-review — just clear this entry.)"; } >> "$NEW_RULES"
  wrote="$wrote rules($(grep -c '^-' <<<"$RULES_TXT"))"
fi

echo "$TODAY" > "$MARKER"
log "OK $TODAY wrote: ${wrote:-nothing-new}"
