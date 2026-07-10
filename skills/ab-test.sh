#!/usr/bin/env bash
# ab-test.sh — Generate A/B test variants for landing page copy elements
# Usage: bash skills/ab-test.sh <product-name> [all|hero|cta|pricing|email-subject] [3-5]
set -euo pipefail

PRODUCT="${1:-}"
ELEMENT="${2:-all}"
N_VARIANTS="${3:-3}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [all|hero|cta|pricing|email-subject] [n-variants: 3-5]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app all 3" >&2
  echo "  $0 bankruptcy-app hero 5" >&2
  echo "  $0 cleardebt cta 4" >&2
  exit 1
fi

# Clamp n-variants to 3-5
if [[ "$N_VARIANTS" -lt 3 ]]; then N_VARIANTS=3; fi
if [[ "$N_VARIANTS" -gt 5 ]]; then N_VARIANTS=5; fi

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

# Primary context: landing page copy (most relevant for A/B testing)
PRODUCT_DESC=""
if [[ -n "$PRODUCT_DIR" && -f "$PRODUCT_DIR/marketing/06-landing-page-copy.md" ]]; then
  PRODUCT_DESC=$(head -c 3000 "$PRODUCT_DIR/marketing/06-landing-page-copy.md")
  echo "Using landing page copy: $PRODUCT_DIR/marketing/06-landing-page-copy.md" >&2
fi

# Fallback: README / PRD + executive summary
if [[ -z "$PRODUCT_DESC" && -n "$PRODUCT_DIR" ]]; then
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
  local prompt="$1" max_tokens="${2:-2000}" outfile="${3:-/tmp/.ab-resp-$$.json}"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt")
  local http_code
  http_code=$(curl -s -o "$outfile" -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$http_code" != "200" ]] && { echo "API error $http_code" >&2; cat "$outfile" >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('$outfile').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
  rm -f "$outfile"
}

# ── Variant output format (injected into both prompts) ───────────────────────
VARIANT_FORMAT="For EACH variant output in this exact format (repeat for all $N_VARIANTS):

### Variant N: [brief descriptive name]
**Copy:** [the actual text]
**Hypothesis:** [one sentence — why this might outperform the control]
**Best for:** [specific audience segment]
**Traffic split:** [recommended % of test traffic]"

# ── Prompt 1: Hero + CTA ─────────────────────────────────────────────────────
HERO_CTA_PROMPT="You are a conversion rate optimisation (CRO) expert specialising in landing page copy.

Product: $PRODUCT
Current landing page copy / context:
$PRODUCT_DESC

Generate $N_VARIANTS A/B test variants each for the HERO section and CTA button.

---
## HERO VARIANTS ($N_VARIANTS variants)
Write $N_VARIANTS alternative H1 headline + subheadline combinations.
- H1: 6-10 words, lead with the single biggest benefit or pain removal
- Subheadline: 15-25 words, clarifies who it's for + what they get
- Test genuinely different angles: pain removal, outcome/benefit, social proof, urgency, curiosity gap

$VARIANT_FORMAT

---
## CTA BUTTON VARIANTS ($N_VARIANTS variants)
Write $N_VARIANTS alternative CTA button labels (3-6 words each).
For each, include one urgency/supporting line (6-12 words) shown directly below the button.
Test angles: action-oriented, outcome-led, risk-removal, curiosity, social proof.

$VARIANT_FORMAT

---
Variants must be meaningfully different — don't just swap synonyms. Be specific to $PRODUCT."

# ── Prompt 2: Pricing + Email Subject ────────────────────────────────────────
PRICING_EMAIL_PROMPT="You are a conversion rate optimisation (CRO) expert specialising in pricing psychology and email marketing.

Product: $PRODUCT
Current landing page copy / context:
$PRODUCT_DESC

Generate $N_VARIANTS A/B test variants each for pricing anchoring and email subject lines.

---
## PRICING ANCHOR VARIANTS ($N_VARIANTS variants)
Write $N_VARIANTS short pricing frame statements (3-8 words) that appear near the price or CTA.
Examples of angles: risk removal ('Free to start'), comparison anchor ('\$0 vs \$2,000 attorney'),
social proof ('Join 10,000 who filed free'), urgency ('Offer ends Friday').

$VARIANT_FORMAT

---
## EMAIL SUBJECT LINE VARIANTS ($N_VARIANTS variants)
Write $N_VARIANTS subject lines for the FIRST lead nurture email after signup.
- Max 50 characters each
- Mix psychological triggers: curiosity gap, personalisation token ([[First Name]]), urgency, benefit-led, question
- Avoid spam triggers (ALL CAPS, excessive punctuation)

$VARIANT_FORMAT

---
Variants must test meaningfully different psychological triggers. Be specific to $PRODUCT."

# ── Parallel execution ────────────────────────────────────────────────────────
NEED_CALL1=false
NEED_CALL2=false
case "$ELEMENT" in
  all)            NEED_CALL1=true; NEED_CALL2=true ;;
  hero|cta)       NEED_CALL1=true ;;
  pricing|email-subject) NEED_CALL2=true ;;
  *)
    echo "Unknown element '$ELEMENT'. Use: all|hero|cta|pricing|email-subject" >&2
    exit 1 ;;
esac

echo "Generating A/B variants for $PRODUCT (element: $ELEMENT, n=$N_VARIANTS)..." >&2

HERO_CTA_FILE="/tmp/.ab-hero-cta-$$.txt"
PRICING_EMAIL_FILE="/tmp/.ab-pricing-email-$$.txt"

# Launch both calls in parallel where needed
if $NEED_CALL1 && $NEED_CALL2; then
  echo "  [1/2] Hero + CTA (parallel)..." >&2
  call_claude "$HERO_CTA_PROMPT" 2200 "/tmp/.ab-api1-$$.json" > "$HERO_CTA_FILE" 2>/tmp/.ab-err1-$$.txt &
  PID1=$!
  echo "  [2/2] Pricing + email subjects (parallel)..." >&2
  call_claude "$PRICING_EMAIL_PROMPT" 2200 "/tmp/.ab-api2-$$.json" > "$PRICING_EMAIL_FILE" 2>/tmp/.ab-err2-$$.txt &
  PID2=$!
  wait $PID1 || { cat /tmp/.ab-err1-$$.txt >&2; exit 1; }
  wait $PID2 || { cat /tmp/.ab-err2-$$.txt >&2; exit 1; }
  rm -f /tmp/.ab-err1-$$.txt /tmp/.ab-err2-$$.txt
elif $NEED_CALL1; then
  echo "  Hero + CTA variants..." >&2
  call_claude "$HERO_CTA_PROMPT" 2200 "/tmp/.ab-api1-$$.json" > "$HERO_CTA_FILE"
elif $NEED_CALL2; then
  echo "  Pricing + email subject variants..." >&2
  call_claude "$PRICING_EMAIL_PROMPT" 2200 "/tmp/.ab-api2-$$.json" > "$PRICING_EMAIL_FILE"
fi

# ── Assemble output ───────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/ab-test-${PRODUCT_LOWER}-${DATE}.md"

{
  echo "# A/B Test Variants — $PRODUCT"
  echo "Generated: $DATE | Element: $ELEMENT | Variants per element: $N_VARIANTS"
  echo "Site: apex.socialtokens.site/bankruptcy/"
  echo
  if [[ -f "$HERO_CTA_FILE" ]]; then
    echo "---"
    echo "## Hero + CTA Variants"
    echo
    cat "$HERO_CTA_FILE"
    echo
  fi
  if [[ -f "$PRICING_EMAIL_FILE" ]]; then
    echo "---"
    echo "## Pricing + Email Subject Variants"
    echo
    cat "$PRICING_EMAIL_FILE"
    echo
  fi
} > "$OUTFILE"

# Save to product marketing folder if it exists
if [[ -n "$PRODUCT_DIR" && -d "$PRODUCT_DIR/marketing" ]]; then
  cp "$OUTFILE" "$PRODUCT_DIR/marketing/09-ab-test-variants.md"
  echo "Also saved to: $PRODUCT_DIR/marketing/09-ab-test-variants.md" >&2
fi

# ── Print to stdout ───────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════"
echo "  A/B TEST VARIANTS — $PRODUCT"
echo "════════════════════════════════════════════════"
echo

if [[ -f "$HERO_CTA_FILE" ]]; then
  echo "## HERO + CTA VARIANTS"
  cat "$HERO_CTA_FILE"
  echo
  echo "---"
  echo
fi

if [[ -f "$PRICING_EMAIL_FILE" ]]; then
  echo "## PRICING + EMAIL SUBJECT VARIANTS"
  cat "$PRICING_EMAIL_FILE"
  echo
fi

echo "════════════════════════════════════════════════"
echo "Saved: $OUTFILE" >&2

# Cleanup
rm -f "$HERO_CTA_FILE" "$PRICING_EMAIL_FILE"
