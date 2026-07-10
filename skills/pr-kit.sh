#!/usr/bin/env bash
# pr-kit.sh — Generate press release + journalist pitches + media list for any Apex product
# Usage: bash skills/pr-kit.sh <product-name> [launch|feature|milestone|funding] [one-line-news-hook]
set -euo pipefail

PRODUCT="${1:-}"
ANGLE="${2:-launch}"
HOOK="${3:-}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [launch|feature|milestone|funding] [news-hook]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app launch 'First AI app to prep bankruptcy filings in 15 minutes'" >&2
  echo "  $0 cleardebt milestone '10,000 users saved average \$4,200 in attorney fees'" >&2
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
[[ -n "$HOOK" ]] && PRODUCT_DESC="NEWS HOOK: $HOOK

$PRODUCT_DESC"

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
  HTTP=$(curl -s -o /tmp/.pr-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.pr-resp.json >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.pr-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

# ── Phase 1: Press release ────────────────────────────────────────────────────
echo "Generating PR kit for $PRODUCT ($ANGLE)..." >&2

PR_PROMPT="You are a PR professional writing for tech and consumer media.

Product: $PRODUCT
Announcement type: $ANGLE
Context:
$PRODUCT_DESC

Write a PRESS RELEASE in AP style format:

FOR IMMEDIATE RELEASE

[HEADLINE — newsworthy, specific, under 12 words]
[SUBHEADLINE — adds the 'why it matters', under 20 words]

[DATELINE — City, Date] — [Opening paragraph: who, what, when, where, why — the entire story in 60 words]

[BODY — 3 paragraphs:
1. The market problem and size (cite realistic figures)
2. How $PRODUCT solves it differently (specific differentiators)
3. A quote from 'the founder' — 2 sentences, conversational, not corporate-speak]

[PRODUCT DETAILS BOX]
- Available: [platform]
- Pricing: [pricing]
- Website: [URL placeholder]
- Launch date: [date]

[BOILERPLATE — 3-sentence company description]

[CONTACT]
Media contact: [Name], [Title]
Email: press@[company].com
Phone: [placeholder]

###

Make it newsworthy. Real journalists delete press releases that read like ads."

# ── Phase 2: 5 journalist pitches ────────────────────────────────────────────
PITCHES_PROMPT="You are a PR professional writing personalised journalist pitches.

Product: $PRODUCT
Announcement type: $ANGLE
Context:
$PRODUCT_DESC

Write 5 SHORT journalist pitch emails — one for each beat/outlet type below.
Each pitch: Subject line + 4-6 sentence email body. First-name only salutation ('Hi [Name],').
The pitch must explain WHY this story fits THEIR specific readership, not just what the product does.
End with: a specific question or story angle offer, not just 'happy to chat.'

---

PITCH 1 — FINTECH / PERSONAL FINANCE REPORTER
Outlets: NerdWallet, Bankrate, The Financial Diet, Business Insider Personal Finance
Angle: Access to financial tools traditionally gatekept by expensive professionals

PITCH 2 — LEGAL TECH REPORTER
Outlets: Law.com, Legal Dive, Above the Law, The American Lawyer
Angle: Technology disrupting how ordinary people access legal processes

PITCH 3 — CONSUMER APP / STARTUP REPORTER
Outlets: TechCrunch, The Verge, Fast Company, Inc.
Angle: App solving a massive underserved problem with a novel approach

PITCH 4 — PERSONAL FINANCE PODCAST / NEWSLETTER
Outlets: Planet Money, How I Built This, Morning Brew, The Hustle
Angle: Human interest — the debt crisis and who actually files for bankruptcy

PITCH 5 — LOCAL / REGIONAL BUSINESS PRESS
Outlets: Local business journals, regional newspapers
Angle: Local startup helping community members navigate financial hardship

Write all 5. Keep each under 120 words. Be specific to $PRODUCT."

# ── Phase 3: Media list + strategy ───────────────────────────────────────────
MEDIA_PROMPT="You are a PR strategist.

Product: $PRODUCT
Announcement type: $ANGLE
Context:
$PRODUCT_DESC

Generate a MEDIA OUTREACH STRATEGY:

## Tier 1 — Dream placements (low probability, high impact)
5 specific publications + why they'd cover this + the hook to use

## Tier 2 — Likely targets (medium probability, high relevance)
8 specific publications + beat reporters to look for (e.g. 'the personal finance reporter')

## Tier 3 — Quick wins (high probability, build momentum)
- 10 newsletters/Substack writers in the personal finance / debt / legal space
- 5 podcast shows that regularly cover consumer financial tools
- 3 Reddit communities where organic posts could go viral

## Timing Strategy
- Optimal day + time to send pitches
- Embargo strategy (yes or no, and why)
- Follow-up cadence

## Story Angles That Will Get Coverage
5 specific angles ranked by newsworthiness for $PRODUCT.
Include what data or stat would make each angle irresistible.

## Headline Templates
5 headlines a journalist might write about $PRODUCT (not your press release headline — what THEY would write)."

echo "  [1/3] Press release..." >&2
PRESS_RELEASE=$(call_claude "$PR_PROMPT" 2000)

echo "  [2/3] Journalist pitches..." >&2
PITCHES=$(call_claude "$PITCHES_PROMPT" 2500)

echo "  [3/3] Media list + strategy..." >&2
MEDIA=$(call_claude "$MEDIA_PROMPT" 2000)

# ── Output ────────────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/pr-kit-${PRODUCT_LOWER}-${ANGLE}-${DATE}.md"

{
  echo "# PR Kit — $PRODUCT ($ANGLE)"
  echo "Generated: $DATE"
  echo
  echo "---"
  echo "## Press Release"
  echo
  echo "$PRESS_RELEASE"
  echo
  echo "---"
  echo "## Journalist Pitches (5 angles)"
  echo
  echo "$PITCHES"
  echo
  echo "---"
  echo "## Media List + Outreach Strategy"
  echo
  echo "$MEDIA"
} > "$OUTFILE"

# Save to product marketing folder if it exists
MKTG_DIR="$PRODUCT_DIR/marketing"
if [[ -n "$PRODUCT_DIR" && -d "$MKTG_DIR" ]]; then
  cp "$OUTFILE" "$MKTG_DIR/07-pr-kit.md"
  echo "Also saved to: $MKTG_DIR/07-pr-kit.md" >&2
fi

echo
echo "════════════════════════════════════════════════"
echo "  PR KIT — $PRODUCT ($ANGLE)"
echo "════════════════════════════════════════════════"
echo
echo "## PRESS RELEASE"
echo "$PRESS_RELEASE"
echo
echo "---"
echo
echo "## PITCHES (5 angles)"
echo "$PITCHES"
echo
echo "---"
echo
echo "## MEDIA STRATEGY"
echo "$MEDIA"
echo
echo "════════════════════════════════════════════════"
echo "Saved: $OUTFILE" >&2

rm -f /tmp/.pr-resp.json
