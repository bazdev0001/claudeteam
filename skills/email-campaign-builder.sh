#!/usr/bin/env bash
# email-campaign-builder.sh — Generate a complete email campaign sequence for any Apex product
# Usage: bash email-campaign-builder.sh <product-name> [goal: launch|nurture|reactivation] [emails: 3-7]
set -euo pipefail

PRODUCT="${1:-}"
GOAL="${2:-launch}"
NUM_EMAILS="${3:-5}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [goal: launch|nurture|reactivation] [num-emails: 3-7]" >&2
  exit 1
fi

# ── Resolve product description ──────────────────────────────────────────────
APEX_DIR="/home/barry/apex/projects"
PRODUCT_LOWER=$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]')

PRODUCT_DIR=""
if [[ -d "$APEX_DIR/$PRODUCT" ]]; then
  PRODUCT_DIR="$APEX_DIR/$PRODUCT"
elif [[ -d "$APEX_DIR/$PRODUCT_LOWER" ]]; then
  PRODUCT_DIR="$APEX_DIR/$PRODUCT_LOWER"
else
  MATCH=$(find "$APEX_DIR" -maxdepth 1 -type d -iname "*${PRODUCT_LOWER}*" | head -1)
  [[ -n "$MATCH" ]] && PRODUCT_DIR="$MATCH"
fi

PRODUCT_DESC=""
if [[ -n "$PRODUCT_DIR" ]]; then
  for candidate in DESIGN.md README.md PRD.md; do
    if [[ -f "$PRODUCT_DIR/$candidate" ]]; then
      PRODUCT_DESC=$(head -c 1000 "$PRODUCT_DIR/$candidate" 2>/dev/null || true)
      break
    fi
  done
fi

[[ -z "$PRODUCT_DESC" ]] && PRODUCT_DESC="$PRODUCT — infer product details from the name."

# ── Goal definitions ─────────────────────────────────────────────────────────
case "$GOAL" in
  launch)
    GOAL_DESC="Product launch sequence — build excitement, announce the product, drive first sign-ups/purchases"
    SEQUENCE_DESC="Email 1: Teaser (coming soon). Email 2: Launch announcement. Email 3: Key benefit deep-dive. Email 4: Social proof/early user story. Email 5+: Urgency/last chance CTA."
    ;;
  nurture)
    GOAL_DESC="Nurture sequence — educate leads, build trust, move them toward conversion over time"
    SEQUENCE_DESC="Email 1: Welcome + set expectations. Email 2: Problem awareness. Email 3: Solution education. Email 4: Case study/proof. Email 5+: Soft conversion offer."
    ;;
  reactivation)
    GOAL_DESC="Reactivation sequence — win back inactive users or trial users who didn't convert"
    SEQUENCE_DESC="Email 1: We miss you. Email 2: What's new since you left. Email 3: Special offer. Email 4+: Final chance / let us know if you want to unsubscribe."
    ;;
  *)
    GOAL_DESC="$GOAL campaign"
    SEQUENCE_DESC="Build a logical ${NUM_EMAILS}-email sequence suited to the goal."
    ;;
esac

# ── Extract bearer token ─────────────────────────────────────────────────────
TOKEN=$(python3 -c "
import json, sys
with open('/home/barry/.claude/.credentials.json') as f:
    d = json.load(f)
tok = (d.get('claudeAiOauth') or {}).get('accessToken') \
   or (d.get('primaryAccount') or {}).get('oauthAccount',{}).get('accessToken') \
   or d.get('oauth_token') \
   or next(iter(d.values())) if d else ''
print(tok)
" 2>/dev/null)

[[ -z "$TOKEN" ]] && { echo "ERROR: no bearer token" >&2; exit 1; }

# ── Build prompt ─────────────────────────────────────────────────────────────
PROMPT="You are an email copywriter for Apex, a portfolio of consumer apps.

Product: $PRODUCT
Campaign goal: $GOAL_DESC
Number of emails: $NUM_EMAILS
Sequence logic: $SEQUENCE_DESC

Product context:
$PRODUCT_DESC

Write exactly $NUM_EMAILS emails. For each email output:

---EMAIL N---
Subject: <subject line>
Preview text: <50-char preview shown in inbox>

<email body — 150-250 words, conversational, clear CTA at the end>

CTA: <button text | destination: where it links>
Send timing: <e.g., Day 0, Day 3, Day 7>
---

Keep subject lines under 50 chars. Write like a human, not a robot. No preamble."

PROMPT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT")

# ── Call Claude via headroom proxy ───────────────────────────────────────────
HTTP_CODE=$(curl -s -o /tmp/.email-campaign-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"claude-haiku-4-5-20251001\",
    \"max_tokens\": 3000,
    \"messages\": [{\"role\": \"user\", \"content\": $PROMPT_JSON}]
  }")

if [[ "$HTTP_CODE" != "200" ]]; then
  >&2 echo "API error HTTP $HTTP_CODE"
  cat /tmp/.email-campaign-resp.json >&2
  exit 1
fi

python3 -c "
import json, sys
resp = json.loads(sys.argv[1])
if 'error' in resp:
    print('API ERROR:', resp['error'], file=sys.stderr)
    sys.exit(1)
for block in resp.get('content', []):
    if block.get('type') == 'text':
        print(block['text'])
" "$(cat /tmp/.email-campaign-resp.json)"
