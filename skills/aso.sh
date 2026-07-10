#!/usr/bin/env bash
# aso.sh — App Store Optimization: generates full listing copy for iOS App Store / Google Play
# Usage: bash skills/aso.sh <product-name> [ios|android|both]
set -euo pipefail

PRODUCT="${1:-}"
STORE="${2:-ios}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [ios|android|both]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app ios" >&2
  echo "  $0 cleardebt both" >&2
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
  for f in README.md DESIGN.md PRD.md MARKETING.md; do
    [[ -f "$PRODUCT_DIR/$f" ]] && PRODUCT_DESC=$(head -c 1500 "$PRODUCT_DIR/$f") && break
  done
  # Also pull marketing folder if present
  [[ -f "$PRODUCT_DIR/marketing/00-executive-summary.md" ]] && \
    PRODUCT_DESC="$PRODUCT_DESC
$(head -c 500 "$PRODUCT_DIR/marketing/00-executive-summary.md")"
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
  local prompt="$1" max_tokens="${2:-2000}"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt")
  HTTP=$(curl -s -o /tmp/.aso-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.aso-resp.json >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.aso-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

# ── Build store-specific context ──────────────────────────────────────────────
if [[ "$STORE" == "ios" || "$STORE" == "both" ]]; then
  echo "Generating iOS App Store listing..." >&2

  IOS_PROMPT="You are an App Store Optimization expert for the iOS App Store.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Generate a COMPLETE iOS App Store listing. Follow character limits exactly.

## App Name
Max 30 characters. Keyword-rich. Lead with the strongest keyword.
Format: [APP NAME] (X chars)

## Subtitle
Max 30 characters. Second-strongest benefit. No word overlap with app name.
Format: [SUBTITLE] (X chars)

## Keywords Field
Max 100 characters total, comma-separated, no spaces after commas. Do NOT repeat words in name or subtitle.
High-volume, relevant search terms. Think: what does someone type when they need this?
Format: [KEYWORD LIST] (X chars)

## Description (4000 chars max)
Structure:
- Opening hook (2 sentences — lead with the user's pain, then the solution)
- 3 feature sections with emoji bullet points
- Social proof / credibility sentence
- Clear CTA
- Legal disclaimer line (important for financial/legal apps)

## Short Description (for search results preview, ~170 chars)
One punchy sentence. Pain → solution → outcome.

## What's New (first release)
2-3 sentences, casual tone, no corporate speak.

## Screenshot Captions (5 screens)
For each: [Screen purpose] → [Caption text — 30 chars max]
Make the captions work as a narrative when viewed in sequence.

## A/B Test Variants
3 alternative App Name + Subtitle pairs to test against the primary.

Be specific to $PRODUCT. Avoid generic phrases like 'easy to use' or 'powerful app.'"

  IOS_OUTPUT=$(call_claude "$IOS_PROMPT" 2500)
fi

if [[ "$STORE" == "android" || "$STORE" == "both" ]]; then
  echo "Generating Google Play Store listing..." >&2

  PLAY_PROMPT="You are an App Store Optimization expert for the Google Play Store.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Generate a COMPLETE Google Play Store listing.

## App Title
Max 30 characters. Lead keyword first.
Format: [TITLE] (X chars)

## Short Description
Max 80 characters. Shown in search results. Benefit-first.
Format: [SHORT DESC] (X chars)

## Full Description (4000 chars max)
Google Play is more text-searchable than iOS — weave keywords naturally throughout.
Structure:
- Hook paragraph (pain point → solution)
- Key features (3-5 bullet sections with headers)
- Who it's for (target audience paragraph)
- Privacy/trust paragraph (especially important for financial apps)
- Download CTA

## Feature Graphic Text
The 1024x500 banner text — 5 words max, benefit statement.

## Target Keywords
15 keywords to embed naturally in the description.

## Content Rating Note
Flag what content rating this app will receive and why.

Be specific to $PRODUCT. Google Play description is HTML-friendly — use line breaks."

  PLAY_OUTPUT=$(call_claude "$PLAY_PROMPT" 2500)
fi

# ── Output & save ─────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/aso-${PRODUCT_LOWER}-${STORE}-${DATE}.md"

{
  echo "# ASO Listing — $PRODUCT ($STORE)"
  echo "Generated: $DATE"
  echo
  if [[ "$STORE" == "ios" || "$STORE" == "both" ]]; then
    echo "---"
    echo "## iOS App Store"
    echo
    echo "$IOS_OUTPUT"
    echo
  fi
  if [[ "$STORE" == "android" || "$STORE" == "both" ]]; then
    echo "---"
    echo "## Google Play Store"
    echo
    echo "$PLAY_OUTPUT"
    echo
  fi
} > "$OUTFILE"

# Save to product marketing folder if it exists
MKTG_DIR="$PRODUCT_DIR/marketing"
if [[ -n "$PRODUCT_DIR" && -d "$MKTG_DIR" ]]; then
  cp "$OUTFILE" "$MKTG_DIR/05-app-store-listing.md"
  echo "Also saved to: $MKTG_DIR/05-app-store-listing.md" >&2
fi

echo
echo "════════════════════════════════════════════════"
echo "  ASO LISTING — $PRODUCT ($STORE)"
echo "════════════════════════════════════════════════"
echo
[[ "$STORE" == "ios" || "$STORE" == "both" ]] && echo "$IOS_OUTPUT"
[[ "$STORE" == "android" || "$STORE" == "both" ]] && echo "$PLAY_OUTPUT"
echo
echo "════════════════════════════════════════════════"
echo "Saved to: $OUTFILE" >&2

rm -f /tmp/.aso-resp.json
