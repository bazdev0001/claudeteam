#!/usr/bin/env bash
# marketing-team.sh — 4 parallel marketing agents → unified 30-day plan
# Usage: bash skills/marketing-team.sh <product-name> [launch|growth|retention]
set -euo pipefail

PRODUCT="${1:-}"
MODE="${2:-growth}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [launch|growth|retention]" >&2
  echo "Modes: launch (new product), growth (scale up), retention (keep users)" >&2
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
  for f in DESIGN.md README.md PRD.md MARKETING.md; do
    [[ -f "$PRODUCT_DIR/$f" ]] && PRODUCT_DESC=$(head -c 1200 "$PRODUCT_DIR/$f") && break
  done
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
  local prompt="$1" max_tokens="${2:-2500}"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt")
  HTTP=$(curl -s -o /tmp/.mkt-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.mkt-resp.json >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.mkt-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

# ── Phase 1: 4 parallel agents (sequential here, fast on haiku) ───────────────
echo "Running 4 marketing agents for $PRODUCT ($MODE mode)..." >&2

CONTENT_PROMPT="You are a content strategy director.

Product: $PRODUCT
Mode: $MODE
Context: $PRODUCT_DESC

Produce a CONTENT STRATEGY for the next 30 days:

## Blog / SEO Content Plan
- 3 pillar articles (title + angle + target keyword + estimated traffic intent)
- 5 supporting articles or landing pages
- Content cadence recommendation

## Email Content Calendar
- Week 1-4 themes
- Key messages per week

## Lead Magnet Ideas
- 3 specific lead magnets this product should offer (with format: PDF, tool, quiz, etc.)

Be specific to $PRODUCT. No generic marketing fluff. Make it actionable."

SEO_PROMPT="You are an SEO strategist.

Product: $PRODUCT
Mode: $MODE
Context: $PRODUCT_DESC

Produce an SEO PLAN for the next 30 days:

## Target Keywords
- 5 primary keywords (high intent, achievable for a new site)
- 10 long-tail keywords (low competition, high relevance)
- 3 competitor keywords to steal

## On-Page Priorities
- Homepage: headline, meta description, H1 recommendation
- Key pages to create or optimise
- Internal linking strategy

## Off-Page / Link Building
- 3 specific link-building tactics suited to $PRODUCT
- Guest post targets or PR angles

## Technical Quick Wins
- Top 3 technical SEO fixes to do this week

Be specific and actionable. No vague advice."

SOCIAL_PROMPT="You are a social media strategist.

Product: $PRODUCT
Mode: $MODE
Context: $PRODUCT_DESC

Produce a SOCIAL MEDIA PLAN for the next 30 days:

## Platform Priorities
Rank: TikTok, Instagram, LinkedIn, Twitter/X, YouTube Shorts — top 3 for this product and why.

## Content Pillars (3 pillars, platform-specific)
For each pillar: hook formula, post frequency, example post ideas (3 each)

## 30-Day Posting Calendar
Week 1-4: what to post each week, on which platform, with what angle

## Viral Hook Templates
5 hook formulas specific to $PRODUCT's pain points (ready to fill in)

## Growth Tactics
3 specific tactics to grow followers in the first 30 days

No generic advice. Write for $PRODUCT's actual audience."

ADS_PROMPT="You are a paid acquisition strategist.

Product: $PRODUCT
Mode: $MODE
Context: $PRODUCT_DESC

Produce a PAID ADS PLAN for the next 30 days:

## Recommended Channels
Top 2 paid channels for $PRODUCT with budget split rationale.

## Ad Creative Brief
For each channel:
- 3 ad headline variants (tested hooks)
- 2 body copy variants
- CTA options
- Visual direction (what the creative should show)

## Audience Segments
3 specific audiences to test first (demographics, interests, behaviors, or lookalikes)

## Budget & Bidding
- Suggested starting monthly budget
- How to split across campaigns
- Key metrics to watch (target CPL, ROAS, CTR benchmarks)

## 30-Day Test Plan
Week 1: what to launch | Week 2-3: what to test | Week 4: what to cut or scale

No vague advice. Be specific to $PRODUCT."

echo "  [1/4] Content strategy..." >&2
CONTENT=$(call_claude "$CONTENT_PROMPT")

echo "  [2/4] SEO plan..." >&2
SEO=$(call_claude "$SEO_PROMPT")

echo "  [3/4] Social media plan..." >&2
SOCIAL=$(call_claude "$SOCIAL_PROMPT")

echo "  [4/4] Paid ads plan..." >&2
ADS=$(call_claude "$ADS_PROMPT" 2000)

# ── Phase 2: Synthesis ────────────────────────────────────────────────────────
echo "  [5/5] Synthesising 30-day marketing plan..." >&2

SYNTHESIS_PROMPT="You are a CMO synthesising a marketing plan.

Product: $PRODUCT
Mode: $MODE

You have 4 specialist reports below. Create a UNIFIED 30-DAY MARKETING PLAN:

## Executive Summary (4 sentences)
What is the overall strategy, why, and what success looks like.

## Week-by-Week Priorities
For each week: top 3 actions across ALL channels (content, SEO, social, ads) — pick the highest-impact ones only.

## Channel Hierarchy
Rank all channels by expected ROI for $PRODUCT at this stage. Be decisive.

## Budget Allocation (if \$5k/month)
How to split across content creation, paid ads, tools, freelancers.

## 3 Bets to Make This Month
Three specific high-conviction moves that could drive outsized results.

---
CONTENT REPORT:
$CONTENT

---
SEO REPORT:
$SEO

---
SOCIAL REPORT:
$SOCIAL

---
ADS REPORT:
$ADS

---
Synthesise into a tight, decisive CMO-level plan. No padding."

SYNTHESIS=$(call_claude "$SYNTHESIS_PROMPT" 3000)

# ── Output ────────────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/marketing-plan-${PRODUCT_LOWER}-${MODE}-${DATE}.md"

{
  echo "# Marketing Plan — $PRODUCT ($MODE mode)"
  echo "Generated: $DATE"
  echo
  echo "---"
  echo
  echo "## Executive Summary + Week-by-Week (CMO Synthesis)"
  echo
  echo "$SYNTHESIS"
  echo
  echo "---"
  echo
  echo "## Content Strategy"
  echo
  echo "$CONTENT"
  echo
  echo "---"
  echo
  echo "## SEO Plan"
  echo
  echo "$SEO"
  echo
  echo "---"
  echo
  echo "## Social Media Plan"
  echo
  echo "$SOCIAL"
  echo
  echo "---"
  echo
  echo "## Paid Ads Plan"
  echo
  echo "$ADS"
} > "$OUTFILE"

echo
echo "════════════════════════════════════════════════"
echo "  MARKETING PLAN — $PRODUCT ($MODE)"
echo "════════════════════════════════════════════════"
echo
echo "$SYNTHESIS"
echo
echo "════════════════════════════════════════════════"
echo "Full report saved: $OUTFILE" >&2

rm -f /tmp/.mkt-resp.json
