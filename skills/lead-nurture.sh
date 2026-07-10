#!/usr/bin/env bash
# lead-nurture.sh — Generate a 5-email lead nurture drip sequence for intake form signups
# Usage: bash skills/lead-nurture.sh <product-name> [persona] [convert|educate|reactivate]
set -euo pipefail

PRODUCT="${1:-}"
PERSONA="${2:-prospect}"
GOAL="${3:-convert}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [persona] [convert|educate|reactivate]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app 'distressed debtor' convert" >&2
  echo "  $0 cleardebt 'someone behind on credit cards' educate" >&2
  echo "  $0 voice-messenger 'small business owner' reactivate" >&2
  exit 1
fi

# ── Product context ───────────────────────────────────────────────────────────
APEX_DIR="/home/barry/apex/projects"
PRODUCT_LOWER=$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]')
PRODUCT_DIR=""
for candidate in "$APEX_DIR/$PRODUCT" "$APEX_DIR/$PRODUCT_LOWER"; do
  [[ -d "$candidate" ]] && PRODUCT_DIR="$candidate" && break
done
[[ -z "$PRODUCT_DIR" ]] && {
  MATCH=$(find "$APEX_DIR" -maxdepth 1 -type d -iname "*${PRODUCT_LOWER}*" 2>/dev/null | head -1)
  [[ -n "$MATCH" ]] && PRODUCT_DIR="$MATCH"
}

PRODUCT_DESC=""
if [[ -n "$PRODUCT_DIR" ]]; then
  for f in README.md DESIGN.md PRD.md; do
    [[ -f "$PRODUCT_DIR/$f" ]] && PRODUCT_DESC=$(head -c 1500 "$PRODUCT_DIR/$f") && break
  done
  [[ -f "$PRODUCT_DIR/marketing/00-executive-summary.md" ]] && \
    PRODUCT_DESC="$PRODUCT_DESC
$(head -c 400 "$PRODUCT_DIR/marketing/00-executive-summary.md")"
fi
[[ -z "$PRODUCT_DESC" ]] && PRODUCT_DESC="$PRODUCT — infer from product name."

# ── Bearer token ──────────────────────────────────────────────────────────────
TOKEN=$(python3 -c "
import json
with open('/home/barry/.claude/.credentials.json') as f:
    d = json.load(f)
tok = (d.get('claudeAiOauth') or {}).get('accessToken') \
   or (d.get('primaryAccount') or {}).get('oauthAccount',{}).get('accessToken','')
print(tok)
" 2>/dev/null)
[[ -z "$TOKEN" ]] && { echo "ERROR: no bearer token" >&2; exit 1; }

call_claude() {
  local prompt="$1" max_tokens="${2:-3000}"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt")
  HTTP=$(curl -s -o /tmp/.nurture-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.nurture-resp.json >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.nurture-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

# ── Shared context block ──────────────────────────────────────────────────────
CTX="Product: $PRODUCT
Persona: $PERSONA
Goal: $GOAL
Context:
$PRODUCT_DESC"

EMAIL_FORMAT='For EACH email output this exact structure:

SUBJECT: [primary subject line]
SUBJECT_B: [A/B variant 1]
SUBJECT_C: [A/B variant 2]
PREVIEW: [preview text, max 100 characters, no emoji]
---BODY---
[Full plain-text email body. 150-250 words. Conversational, empathetic, no corporate-speak.
First line is NOT "I hope this email finds you well."
End with a single clear next step.]
---HTML---
<p>[opening hook — 1 sentence]</p>
<p>[body paragraph 1]</p>
<p>[body paragraph 2]</p>
<p>[CTA context sentence]</p>
<p><strong>[CTA_BUTTON: button label | {{CTA_URL}}]</strong></p>
---END---'

# ── Phase 1: Emails 1-2 ───────────────────────────────────────────────────────
PROMPT_12="You are an expert email copywriter specialising in high-converting lead nurture sequences.

$CTX

Write EMAIL 1 and EMAIL 2 of a 5-email drip sequence. The goal is: $GOAL.

EMAIL 1 — Day 0 (sent immediately after form submission)
Purpose: Welcome + set expectations for what happens next.
Tone: Warm, reassuring, human. They just raised their hand — make them feel they made a smart move.
Must include: what they can expect from you, what the next step is, and a low-friction first CTA (e.g. read an article, watch a short video, or complete a profile).

EMAIL 2 — Day 2
Purpose: Educational. Teach them the #1 thing they need to understand about their situation (problem awareness).
Tone: Helpful expert, not salesy. Position $PRODUCT as the guide, not the hero — THEY are the hero.
Must include: a surprising or counter-intuitive insight, a brief explanation of why most people get this wrong, and a CTA that deepens engagement.

$EMAIL_FORMAT

Separate the two emails with: === EMAIL BREAK ==="

# ── Phase 2: Emails 3-4 ───────────────────────────────────────────────────────
PROMPT_34="You are an expert email copywriter specialising in high-converting lead nurture sequences.

$CTX

Write EMAIL 3 and EMAIL 4 of a 5-email drip sequence. The goal is: $GOAL.

EMAIL 3 — Day 4
Purpose: Social proof. Tell a story from someone like them who succeeded using $PRODUCT.
Tone: Storytelling — open with a relatable situation, arc to the transformation, close with a bridge to the reader's own situation.
Must include: a named or lightly anonymised persona ('Sarah, a 38-year-old nurse from Ohio…'), a specific outcome (numbers or time), and a CTA to take the same first step.

EMAIL 4 — Day 7
Purpose: Objection handler. Address the top 3 reasons people like $PERSONA hesitate to proceed.
Tone: Empathetic and direct. Acknowledge the objection before refuting it — never dismiss.
Structure: Use a short intro, then handle each objection with a header or bold label, then close with a confidence-building CTA.
Common objections to address (adapt to $PRODUCT): 'It costs too much', 'I'm not sure I qualify', 'I'm worried about the consequences'.

$EMAIL_FORMAT

Separate the two emails with: === EMAIL BREAK ==="

# ── Phase 3: Email 5 ─────────────────────────────────────────────────────────
PROMPT_5="You are an expert email copywriter specialising in high-converting lead nurture sequences.

$CTX

Write EMAIL 5 of a 5-email drip sequence. The goal is: $GOAL.

EMAIL 5 — Day 10
Purpose: Urgency / final CTA. Time-sensitive nudge to complete the process.
Tone: Direct, honest, not manipulative. Explain why NOW is the right time (not a fake countdown — use real reasons: their situation won't improve on its own, the process takes time, early action = more options).
Must include: a brief recap of what they can achieve, a frank acknowledgement that many people put this off and what happens when they do, a strong primary CTA, and a soft secondary option for people not ready to commit (e.g. 'Not ready? Reply and tell me your biggest concern — I read every reply.').

$EMAIL_FORMAT"

# ── Run all three calls ───────────────────────────────────────────────────────
echo "Generating lead nurture sequence for $PRODUCT ($PERSONA, goal: $GOAL)..." >&2

echo "  [1/3] Emails 1-2 (welcome + education)..." >&2
EMAILS_12=$(call_claude "$PROMPT_12" 3000)

echo "  [2/3] Emails 3-4 (social proof + objections)..." >&2
EMAILS_34=$(call_claude "$PROMPT_34" 3000)

echo "  [3/3] Email 5 (urgency + CTA)..." >&2
EMAIL_5=$(call_claude "$PROMPT_5" 2000)

# ── Output ────────────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/lead-nurture-${PRODUCT_LOWER}-${DATE}.md"

{
  echo "# Lead Nurture Sequence — $PRODUCT"
  echo "Generated: $DATE | Persona: $PERSONA | Goal: $GOAL"
  echo
  echo "---"
  echo "## Email 1 (Day 0) + Email 2 (Day 2)"
  echo
  echo "$EMAILS_12"
  echo
  echo "---"
  echo "## Email 3 (Day 4) + Email 4 (Day 7)"
  echo
  echo "$EMAILS_34"
  echo
  echo "---"
  echo "## Email 5 (Day 10)"
  echo
  echo "$EMAIL_5"
} > "$OUTFILE"

# Save to product marketing folder if it exists
MKTG_DIR="$PRODUCT_DIR/marketing"
if [[ -n "$PRODUCT_DIR" && -d "$MKTG_DIR" ]]; then
  cp "$OUTFILE" "$MKTG_DIR/08-lead-nurture-sequence.md"
  echo "Also saved to: $MKTG_DIR/08-lead-nurture-sequence.md" >&2
fi

echo
echo "════════════════════════════════════════════════"
echo "  LEAD NURTURE — $PRODUCT ($GOAL)"
echo "════════════════════════════════════════════════"
echo
echo "## EMAILS 1-2 (Day 0 + Day 2)"
echo "$EMAILS_12"
echo
echo "---"
echo
echo "## EMAILS 3-4 (Day 4 + Day 7)"
echo "$EMAILS_34"
echo
echo "---"
echo
echo "## EMAIL 5 (Day 10)"
echo "$EMAIL_5"
echo
echo "════════════════════════════════════════════════"
echo "Saved: $OUTFILE" >&2

rm -f /tmp/.nurture-resp.json
