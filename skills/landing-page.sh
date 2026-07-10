#!/usr/bin/env bash
# landing-page.sh — Generate complete landing page copy for any Apex product
# Usage: bash skills/landing-page.sh <product-name> [persona] [tone: professional|conversational|urgent]
set -euo pipefail

PRODUCT="${1:-}"
PERSONA="${2:-distressed debtor}"
TONE="${3:-conversational}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [target-persona] [tone: professional|conversational|urgent]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app 'stressed debtor' urgent" >&2
  echo "  $0 cleardebt 'small business owner' professional" >&2
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
MARKETING_CONTEXT=""
if [[ -n "$PRODUCT_DIR" ]]; then
  for f in README.md DESIGN.md PRD.md; do
    [[ -f "$PRODUCT_DIR/$f" ]] && PRODUCT_DESC=$(head -c 1200 "$PRODUCT_DIR/$f") && break
  done
  [[ -f "$PRODUCT_DIR/marketing/00-executive-summary.md" ]] && \
    MARKETING_CONTEXT=$(head -c 600 "$PRODUCT_DIR/marketing/00-executive-summary.md")
  [[ -f "$PRODUCT_DIR/marketing/02-seo-plan.md" ]] && \
    MARKETING_CONTEXT="$MARKETING_CONTEXT
$(grep -A5 'Primary\|primary\|Target Keyword\|target keyword' "$PRODUCT_DIR/marketing/02-seo-plan.md" 2>/dev/null | head -15)"
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
  HTTP=$(curl -s -o /tmp/.lp-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.lp-resp.json >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.lp-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

# ── Phase 1: Above-the-fold + hero ────────────────────────────────────────────
echo "Generating landing page copy for $PRODUCT..." >&2

HERO_PROMPT="You are a conversion copywriter. Write for a $TONE tone targeting: $PERSONA.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Marketing context:
$MARKETING_CONTEXT

Generate the ABOVE-THE-FOLD section of the landing page:

## NAV BAR
- Logo text / wordmark
- 3 nav links
- CTA button text

## HERO SECTION
- H1 headline (8 words max — lead with the outcome, not the product)
- Subheadline (20 words max — who it's for + how it works)
- Hero CTA button text
- Secondary link text (e.g. 'See how it works ↓')
- Social proof line (e.g. '2,400 people filed last month with no lawyer')

## 3 HEADLINE VARIANTS TO A/B TEST
Alternative H1 options ranked by predicted conversion rate with one-line rationale.

## TRUST BAR
4 trust signals (icons + short labels): e.g. 'Bank-level encryption', 'No credit card required', '15-min assessment', 'Attorney-reviewed'

Write punchy, specific copy. No filler words. Speak directly to the $PERSONA's fear or desire."

# ── Phase 2: Problem/solution + features ──────────────────────────────────────
FEATURES_PROMPT="You are a conversion copywriter. Write for a $TONE tone targeting: $PERSONA.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Generate the MIDDLE sections of the landing page:

## PROBLEM SECTION
- Section headline (agitate the pain)
- 3 bullet points: specific problems the $PERSONA faces (be visceral and specific)
- Bridge sentence leading to the solution

## SOLUTION SECTION
- Section headline ('Introducing $PRODUCT' or similar reveal)
- 2-sentence product description in plain English
- 3 FEATURE BLOCKS (each with):
  - Emoji icon
  - Feature name (3 words max)
  - Benefit headline (8 words max)
  - Description (25 words max — outcome-focused, not feature-focused)

## HOW IT WORKS (3 steps)
- Section headline
- Step 1: [action] → [result]
- Step 2: [action] → [result]
- Step 3: [action] → [result]
Each step: name (3 words) + description (15 words)

## SOCIAL PROOF SECTION
- Section headline
- 3 testimonial templates (fill in with real data later):
  [Name, location, situation] — quote focused on a specific result
  Keep quotes under 40 words. Make them sound real, not corporate.
- 1 stat block: 3 numbers that would matter to the $PERSONA

No generic copy. Every word should make the $PERSONA feel understood."

# ── Phase 3: FAQ + CTA + footer ───────────────────────────────────────────────
CLOSE_PROMPT="You are a conversion copywriter. Write for a $TONE tone targeting: $PERSONA.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Generate the CLOSING sections of the landing page:

## FAQ SECTION
- Section headline
- 6 FAQs that address real objections from $PERSONA:
  Q: [question]
  A: [answer — 2-3 sentences, direct, no hedging]

  Cover: cost, privacy, how it compares to a lawyer, what happens after, eligibility, timeline.

## FINAL CTA SECTION
- Headline (restate the core promise)
- Subtext (remove last objection / add urgency without being sleazy)
- Primary CTA button
- Risk-reversal line (e.g. 'Free to start. No credit card.')
- Secondary reassurance (e.g. 'Join 2,400 people who took control of their debt')

## FOOTER
- Tagline (one sentence under the logo)
- Legal disclaimer (2 sentences — important for financial/legal products)
- 4 footer link categories with 3 links each

Make the FAQ answers feel like a knowledgeable friend talking, not a legal document."

echo "  [1/3] Hero + nav..." >&2
HERO=$(call_claude "$HERO_PROMPT" 1500)

echo "  [2/3] Problem/solution/features..." >&2
FEATURES=$(call_claude "$FEATURES_PROMPT" 2000)

echo "  [3/3] FAQ + CTA + footer..." >&2
CLOSE=$(call_claude "$CLOSE_PROMPT" 2000)

# ── Output ────────────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/landing-page-${PRODUCT_LOWER}-${DATE}.md"

{
  echo "# Landing Page Copy — $PRODUCT"
  echo "Generated: $DATE | Persona: $PERSONA | Tone: $TONE"
  echo
  echo "$HERO"
  echo
  echo "---"
  echo
  echo "$FEATURES"
  echo
  echo "---"
  echo
  echo "$CLOSE"
} > "$OUTFILE"

# Save to product marketing folder if it exists
MKTG_DIR="$PRODUCT_DIR/marketing"
if [[ -n "$PRODUCT_DIR" && -d "$MKTG_DIR" ]]; then
  cp "$OUTFILE" "$MKTG_DIR/06-landing-page-copy.md"
  echo "Also saved to: $MKTG_DIR/06-landing-page-copy.md" >&2
fi

echo
echo "════════════════════════════════════════════════"
echo "  LANDING PAGE — $PRODUCT"
echo "  Persona: $PERSONA | Tone: $TONE"
echo "════════════════════════════════════════════════"
echo
echo "$HERO"
echo
echo "---"
echo
echo "$FEATURES"
echo
echo "---"
echo
echo "$CLOSE"
echo
echo "════════════════════════════════════════════════"
echo "Saved: $OUTFILE" >&2

rm -f /tmp/.lp-resp.json
