#!/usr/bin/env bash
# competitor-analysis.sh — Analyse competitors and generate positioning report for any Apex product
# Usage: bash skills/competitor-analysis.sh <product-name> [niche-description]
set -euo pipefail

PRODUCT="${1:-}"
NICHE="${2:-}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [niche-description]" >&2
  echo "Examples:" >&2
  echo "  $0 cleardebt 'debt settlement app for consumers'" >&2
  echo "  $0 voice-messenger 'voice messaging PWA'" >&2
  exit 1
fi

# ── Load product context ──────────────────────────────────────────────────────
APEX_DIR="/home/barry/apex/projects"
PRODUCT_LOWER=$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]')
PRODUCT_DIR=""
for candidate in "$APEX_DIR/$PRODUCT" "$APEX_DIR/$PRODUCT_LOWER"; do
  [[ -d "$candidate" ]] && PRODUCT_DIR="$candidate" && break
done
if [[ -z "$PRODUCT_DIR" ]]; then
  MATCH=$(find "$APEX_DIR" -maxdepth 1 -type d -iname "*${PRODUCT_LOWER}*" 2>/dev/null | head -1)
  [[ -n "$MATCH" ]] && PRODUCT_DIR="$MATCH"
fi

PRODUCT_DESC=""
if [[ -n "$PRODUCT_DIR" ]]; then
  for f in DESIGN.md README.md PRD.md; do
    [[ -f "$PRODUCT_DIR/$f" ]] && PRODUCT_DESC=$(head -c 1000 "$PRODUCT_DIR/$f") && break
  done
fi
[[ -z "$PRODUCT_DESC" ]] && PRODUCT_DESC="$PRODUCT — infer from product name and niche."
[[ -n "$NICHE" ]] && PRODUCT_DESC="Niche: $NICHE

$PRODUCT_DESC"

# ── Bearer token ──────────────────────────────────────────────────────────────
TOKEN=$(python3 -c "
import json
with open('/home/barry/.claude/.credentials.json') as f:
    d = json.load(f)
tok = (d.get('claudeAiOauth') or {}).get('accessToken') \
   or (d.get('primaryAccount') or {}).get('oauthAccount',{}).get('accessToken') \
   or next(iter(d.values())) if d else ''
print(tok)
" 2>/dev/null)
[[ -z "$TOKEN" ]] && { echo "ERROR: no bearer token" >&2; exit 1; }

# ── Phase 1: Identify competitors ────────────────────────────────────────────
echo "Identifying competitors for $PRODUCT..." >&2

PHASE1_PROMPT=$(python3 - "$PRODUCT" "$PRODUCT_DESC" << 'PYEOF'
import sys
product = sys.argv[1]
context = sys.argv[2]
print(f"""You are a JSON API. Respond with ONLY valid JSON, no text, no questions, no preamble.

Product: {product}
Context: {context}

Output a JSON array of the top 6 real competitors. Use your training knowledge. Never ask for input.

Example format:
[
  {{
    "name": "CompetitorName",
    "url": "https://their-domain.com",
    "positioning": "one-line positioning statement",
    "pricing_model": "free|freemium|subscription|one-time|usage-based|enterprise",
    "price_range": "e.g. 29/mo or free or enterprise",
    "target_customer": "who they target",
    "key_features": ["feature1", "feature2", "feature3"],
    "strengths": ["strength1", "strength2"],
    "weaknesses": ["weakness1", "weakness2"],
    "funding_stage": "bootstrapped|seed|series-a|series-b|public|unknown"
  }}
]

Output the JSON array now. No other text.""")
PYEOF
)

PHASE1_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PHASE1_PROMPT")

HTTP=$(curl -s -o /tmp/.comp-phase1.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"claude-haiku-4-5-20251001\",
    \"max_tokens\": 3000,
    \"messages\": [{\"role\": \"user\", \"content\": $PHASE1_JSON}]
  }")

[[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.comp-phase1.json >&2; exit 1; }

COMPETITORS=$(python3 -c "
import json, sys, re
resp = json.loads(open('/tmp/.comp-phase1.json').read())
text = ''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text')
# Extract JSON array
m = re.search(r'\[.*\]', text, re.DOTALL)
print(m.group(0) if m else text)
")

# ── Phase 2: Positioning analysis ────────────────────────────────────────────
echo "Generating positioning report..." >&2

PHASE2_PROMPT="You are a startup strategist and product positioning expert.

Product we are building: $PRODUCT
Context:
$PRODUCT_DESC

Competitor landscape:
$COMPETITORS

Produce a POSITIONING REPORT with these sections:

## Market Map
Summarise the competitive landscape in 3-4 sentences. What's crowded, what's empty.

## Competitor Profiles (brief)
For each competitor: 1-line summary of what makes them strong/weak.

## Positioning Gaps
List 3-5 specific unmet needs or underserved segments in this market.
Format: **Gap**: [description] → **Opportunity**: [how $PRODUCT could own it]

## Recommended Positioning for $PRODUCT
- **Primary positioning statement** (one sentence, for the homepage)
- **Target customer** (1-2 sentences)
- **Key differentiators** (3 bullet points — things $PRODUCT should lead with)
- **What to avoid** (what NOT to copy from competitors)

## Pricing Intelligence
- What competitors charge (summary table)
- Recommended pricing strategy for $PRODUCT
- Suggested price point with rationale

## Quick Wins
3 specific things $PRODUCT can do in the next 30 days to differentiate from the top competitors.

Keep it sharp and actionable. No fluff."

PHASE2_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PHASE2_PROMPT")

HTTP=$(curl -s -o /tmp/.comp-phase2.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"claude-haiku-4-5-20251001\",
    \"max_tokens\": 4000,
    \"messages\": [{\"role\": \"user\", \"content\": $PHASE2_JSON}]
  }")

[[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.comp-phase2.json >&2; exit 1; }

REPORT=$(python3 -c "
import json
resp = json.loads(open('/tmp/.comp-phase2.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
")

# ── Output ────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════"
echo "  COMPETITOR ANALYSIS — $PRODUCT"
echo "═══════════════════════════════════════════════════════════"
echo
echo "## Identified Competitors"
echo "$COMPETITORS" | python3 -c "
import json, sys
try:
    comps = json.loads(sys.stdin.read())
    for c in comps:
        print(f\"  • {c['name']} ({c['url']}) — {c['pricing_model']}, {c.get('price_range','?')}\")
        print(f\"    Positioning: {c['positioning']}\")
        print()
except:
    pass
"
echo
echo "$REPORT"
echo
echo "═══════════════════════════════════════════════════════════"

# ── Save to vault ─────────────────────────────────────────────────────────────
OUTFILE="/home/barry/projects/obsidian/notes/competitor-analysis-${PRODUCT_LOWER}-$(date +%Y%m%d).md"
{
  echo "# Competitor Analysis — $PRODUCT"
  echo "Generated: $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "## Raw Competitor Data"
  echo '```json'
  echo "$COMPETITORS"
  echo '```'
  echo
  echo "$REPORT"
} > "$OUTFILE"
echo "Saved to: $OUTFILE" >&2

rm -f /tmp/.comp-phase1.json /tmp/.comp-phase2.json
