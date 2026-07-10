#!/usr/bin/env bash
# seo-audit.sh — SEO audit for any URL or Apex product
# Usage: bash skills/seo-audit.sh <url-or-product-name> [product-context]
# Examples:
#   bash skills/seo-audit.sh https://cleardebt.app
#   bash skills/seo-audit.sh cleardebt 'debt settlement app'
#   bash skills/seo-audit.sh voice-messenger
set -euo pipefail

INPUT="${1:-}"
EXTRA_CONTEXT="${2:-}"

if [[ -z "$INPUT" ]]; then
  echo "Usage: $0 <url-or-product-name> [extra-context]" >&2
  exit 1
fi

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

# ── Determine input type: URL or product name ─────────────────────────────────
PAGE_CONTENT=""
PRODUCT_NAME=""
TARGET_URL=""

if [[ "$INPUT" == http://* ]] || [[ "$INPUT" == https://* ]]; then
  TARGET_URL="$INPUT"
  PRODUCT_NAME=$(echo "$INPUT" | sed 's|https\?://||;s|www\.||;s|/.*||')
  echo "Fetching $TARGET_URL..." >&2
  # Fetch page HTML (text only, strip tags)
  PAGE_CONTENT=$(curl -sf --max-time 15 -L \
    -H "User-Agent: Mozilla/5.0 (compatible; SEO-Audit/1.0)" \
    "$TARGET_URL" 2>/dev/null | python3 -c "
import sys, re
html = sys.stdin.read()
# Strip scripts/styles
html = re.sub(r'<(script|style)[^>]*>.*?</(script|style)>', '', html, flags=re.DOTALL|re.IGNORECASE)
# Extract title
title_m = re.search(r'<title[^>]*>(.*?)</title>', html, re.IGNORECASE|re.DOTALL)
title = title_m.group(1).strip() if title_m else 'NOT FOUND'
# Extract meta description
desc_m = re.search(r'<meta[^>]+name=[\"\\']description[\"\\'][^>]+content=[\"\\']([^\"\\']+)', html, re.IGNORECASE)
if not desc_m:
    desc_m = re.search(r'<meta[^>]+content=[\"\\']([^\"\\']+)[\"\\'][^>]+name=[\"\\']description', html, re.IGNORECASE)
desc = desc_m.group(1).strip() if desc_m else 'NOT FOUND'
# Extract h1-h3
headings = re.findall(r'<h([1-3])[^>]*>(.*?)</h\1>', html, re.IGNORECASE|re.DOTALL)
heading_text = [(f'H{level}', re.sub(r'<[^>]+>', '', text).strip()) for level, text in headings[:20]]
# Extract OG tags
og = re.findall(r'<meta[^>]+property=[\"\\']og:([^\"\\']+)[\"\\'][^>]+content=[\"\\']([^\"\\']+)', html, re.IGNORECASE)
# Strip remaining tags for body text sample
body = re.sub(r'<[^>]+>', ' ', html)
body = re.sub(r'\s+', ' ', body).strip()[:3000]
print(f'TITLE: {title}')
print(f'META DESCRIPTION: {desc}')
print(f'HEADINGS: {heading_text}')
print(f'OG TAGS: {dict(og[:8])}')
print(f'BODY SAMPLE: {body}')
" 2>/dev/null) || PAGE_CONTENT="Could not fetch page — analyze based on URL and context only."
else
  PRODUCT_NAME="$INPUT"
  APEX_DIR="/home/barry/apex/projects"
  PRODUCT_LOWER=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]')
  PRODUCT_DIR=""
  for candidate in "$APEX_DIR/$INPUT" "$APEX_DIR/$PRODUCT_LOWER"; do
    [[ -d "$candidate" ]] && PRODUCT_DIR="$candidate" && break
  done
  if [[ -z "$PRODUCT_DIR" ]]; then
    MATCH=$(find "$APEX_DIR" -maxdepth 1 -type d -iname "*${PRODUCT_LOWER}*" 2>/dev/null | head -1)
    [[ -n "$MATCH" ]] && PRODUCT_DIR="$MATCH"
  fi
  if [[ -n "$PRODUCT_DIR" ]]; then
    for f in DESIGN.md README.md PRD.md; do
      [[ -f "$PRODUCT_DIR/$f" ]] && PAGE_CONTENT=$(head -c 2000 "$PRODUCT_DIR/$f") && break
    done
  fi
  [[ -z "$PAGE_CONTENT" ]] && PAGE_CONTENT="$PRODUCT_NAME — no local files found. Infer from product name."
fi

# ── Build prompt ──────────────────────────────────────────────────────────────
PROMPT=$(python3 - "$PRODUCT_NAME" "${TARGET_URL:-N/A}" "$PAGE_CONTENT" "$EXTRA_CONTEXT" << 'PYEOF'
import sys
product, url, content, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
print(f"""You are an expert SEO consultant. Analyse the following and produce a prioritised SEO audit report.

Product: {product}
URL: {url}
Extra context: {extra if extra else "none"}

Page content / product description:
{content}

## SEO AUDIT REPORT

Produce a structured report with these sections:

### 1. Quick Wins (do this week)
List 3-5 specific, actionable fixes that will have the biggest impact fastest. For each:
- **Issue**: what's wrong
- **Fix**: exactly what to change
- **Impact**: why it matters

### 2. On-Page SEO Analysis
- Title tag: assess length, keyword placement, CTR appeal (ideal: 50-60 chars)
- Meta description: assess length, CTA, keywords (ideal: 150-160 chars)
- H1/H2 structure: logical hierarchy, keyword usage
- Content quality signals: E-E-A-T, readability, comprehensiveness

### 3. Target Keywords
List 8-10 high-value keywords this page/product SHOULD rank for:
- Primary keyword (highest volume, most relevant)
- Secondary keywords (supporting terms)
- Long-tail opportunities (lower competition, high intent)
For each: estimated intent (informational/commercial/transactional)

### 4. Competitor Gap
Based on what you know about this market: what are competitors likely ranking for that this product is missing? List 3-5 gaps.

### 5. Technical SEO Checklist
Rate each (✅ likely good / ⚠️ unknown / ❌ likely issue):
- Page speed
- Mobile responsiveness
- HTTPS
- Schema markup
- Canonical tags
- XML sitemap
- Internal linking
- Image alt tags

### 6. 30-Day SEO Action Plan
Prioritised list of what to do in the next 30 days. Be specific — name the pages, keywords, and actions.

Keep it sharp and actionable. Skip generic advice — every recommendation must be specific to {product}.""")
PYEOF
)

PROMPT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT")

# ── Call Claude ───────────────────────────────────────────────────────────────
echo "Running SEO audit for ${PRODUCT_NAME}..." >&2
HTTP=$(curl -s -o /tmp/.seo-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d "{
    \"model\": \"claude-haiku-4-5-20251001\",
    \"max_tokens\": 4000,
    \"messages\": [{\"role\": \"user\", \"content\": $PROMPT_JSON}]
  }")

[[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.seo-resp.json >&2; exit 1; }

REPORT=$(python3 -c "
import json
resp = json.loads(open('/tmp/.seo-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
")

# ── Output ────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════"
echo "  SEO AUDIT — ${PRODUCT_NAME}"
[[ -n "$TARGET_URL" ]] && echo "  URL: $TARGET_URL"
echo "═══════════════════════════════════════════════════════════"
echo
echo "$REPORT"
echo

# ── Save to vault ─────────────────────────────────────────────────────────────
SLUG=$(echo "$PRODUCT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//')
OUTFILE="/home/barry/projects/obsidian/notes/seo-audit-${SLUG}-$(date +%Y%m%d).md"
{
  echo "# SEO Audit — ${PRODUCT_NAME}"
  echo "Generated: $(date '+%Y-%m-%d %H:%M')"
  [[ -n "$TARGET_URL" ]] && echo "URL: $TARGET_URL"
  echo
  echo "$REPORT"
} > "$OUTFILE"
echo "Saved: $OUTFILE" >&2

rm -f /tmp/.seo-resp.json
