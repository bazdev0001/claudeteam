#!/usr/bin/env bash
# geo-check.sh — GEO (Generative Engine Optimization) auditor
# Usage: bash skills/geo-check.sh <url>
# Checks: robots.txt, llms.txt, Cloudflare blocking, schema.org, meta noai
# Requirements: curl, grep (always available)

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "Usage: $0 <url>"
  echo "Example: $0 https://apex.socialtokens.site"
  exit 1
fi

# Strip trailing slash, extract scheme+host
BASE_URL=$(echo "$URL" | sed 's|/*$||' | grep -oP '^https?://[^/]+')
if [[ -z "$BASE_URL" ]]; then
  echo "ERROR: Could not parse URL. Include http:// or https://"
  exit 1
fi

DOMAIN=$(echo "$BASE_URL" | sed 's|https\?://||')
CURL_OPTS="-s -L --max-time 10 --connect-timeout 5"

# Helpers
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; }
warn() { echo "  WARN: $1"; }
info() { echo "     -> $1"; }

# count_matches: safe grep -c that won't cause issues on zero matches
# grep -c always outputs the count even when returning exit code 1 (no matches)
# We use variable assignment so the || n=0 only fires on actual errors
count_matches() {
  local pattern="$1"
  local text="$2"
  local n
  n=$(echo "$text" | grep -ic "$pattern" 2>/dev/null) || n=0
  echo "$n"
}

echo ""
echo "========================================"
echo "  GEO Checker -- AI Crawler Audit"
echo "  Target: $BASE_URL"
echo "  Page:   $URL"
echo "========================================"
echo ""

# ─────────────────────────────────────────────
# 1. ROBOTS.TXT
# ─────────────────────────────────────────────
echo "1. robots.txt"
ROBOTS_URL="${BASE_URL}/robots.txt"
ROBOTS_STATUS=$(curl $CURL_OPTS -o /tmp/geo_robots.txt -w "%{http_code}" "$ROBOTS_URL" 2>/dev/null || echo "000")
ROBOTS=$(cat /tmp/geo_robots.txt 2>/dev/null || echo "")

ROBOTS_SCORE=0
ROBOTS_BLOCKS=()
AI_BOTS=("GPTBot" "ClaudeBot" "PerplexityBot" "CCBot" "anthropic-ai" "cohere-ai")

if [[ "$ROBOTS_STATUS" != "200" ]]; then
  warn "robots.txt not found or unreachable (HTTP $ROBOTS_STATUS)"
  info "Create /robots.txt — even a permissive one signals good practice"
  info "Minimal: User-agent: *  /  Allow: /"
  ROBOTS_SCORE=1
else
  for BOT in "${AI_BOTS[@]}"; do
    # Extract the block for this user-agent
    BOT_SECTION=$(echo "$ROBOTS" | awk "
      /^[Uu]ser-agent:.*${BOT}/,/^[Uu]ser-agent:/ { print }
    " | head -20)
    if echo "$BOT_SECTION" | grep -qiP "^Disallow:\s*/\s*$"; then
      ROBOTS_BLOCKS+=("$BOT")
    fi
  done

  if [[ ${#ROBOTS_BLOCKS[@]} -gt 0 ]]; then
    fail "AI bots explicitly blocked: ${ROBOTS_BLOCKS[*]}"
    info "Fix: Remove 'Disallow: /' for these bots, or add explicit 'Allow: /'"
    ROBOTS_SCORE=0
  else
    pass "No AI crawler blocks found in robots.txt"
    ROBOTS_SCORE=2
  fi

  # Show AI-relevant lines
  RELEVANT=$(echo "$ROBOTS" | grep -iP "(GPTBot|ClaudeBot|PerplexityBot|CCBot|anthropic|User-agent: \*|Disallow|Allow)" | head -12)
  if [[ -n "$RELEVANT" ]]; then
    info "Relevant lines from robots.txt:"
    while IFS= read -r line; do
      info "  $line"
    done <<< "$RELEVANT"
  fi
fi

echo ""

# ─────────────────────────────────────────────
# 2. LLMS.TXT
# ─────────────────────────────────────────────
echo "2. llms.txt (AI-friendly content standard)"
LLMS_STATUS=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "${BASE_URL}/llms.txt" 2>/dev/null || echo "000")

if [[ "$LLMS_STATUS" == "200" ]]; then
  pass "/llms.txt exists — site is AI-content-ready"
  LLMS_SCORE=2
else
  fail "/llms.txt not found (HTTP $LLMS_STATUS)"
  info "Add /llms.txt to describe your content for LLMs (see llmstxt.org)"
  info "Example: # ${DOMAIN}  /  > AI legal research platform  /  ## Pages  /  - [Home](${BASE_URL}/): Main"
  LLMS_SCORE=0
fi

echo ""

# ─────────────────────────────────────────────
# 3. CLOUDFLARE AI BLOCKING
# ─────────────────────────────────────────────
echo "3. Cloudflare AI blocking"
# Fetch headers twice: normal UA and as GPTBot
CF_HEADERS_STANDARD=$(curl $CURL_OPTS -I "$URL" 2>/dev/null || echo "FETCH_FAILED")
CF_HEADERS_GPTBOT=$(curl $CURL_OPTS -I -A "GPTBot/1.2 (+https://openai.com/gptbot)" "$URL" 2>/dev/null || echo "FETCH_FAILED")

CF_SCORE=2
CF_BLOCK_SIGNALS=()

if [[ "$CF_HEADERS_STANDARD" == "FETCH_FAILED" ]]; then
  warn "Could not reach $URL to check headers"
  CF_SCORE=1
else
  # Check HTTP response code difference
  STANDARD_CODE=$(echo "$CF_HEADERS_STANDARD" | grep -oP "HTTP/\S+ \K\d{3}" | tail -1)
  BOT_CODE=$(echo "$CF_HEADERS_GPTBOT" | grep -oP "HTTP/\S+ \K\d{3}" | tail -1)

  if [[ "$BOT_CODE" =~ ^(403|503|429)$ ]] && [[ "$STANDARD_CODE" == "200" ]]; then
    CF_BLOCK_SIGNALS+=("HTTP $BOT_CODE returned to GPTBot user-agent (normal browser gets $STANDARD_CODE)")
  fi

  # cf-mitigated header signals a bot challenge
  if echo "$CF_HEADERS_GPTBOT" | grep -qi "cf-mitigated"; then
    CF_BLOCK_SIGNALS+=("cf-mitigated header detected (Cloudflare bot challenge triggered)")
  fi

  # x-robots-tag: noindex in headers
  if echo "$CF_HEADERS_STANDARD" | grep -qiP "x-robots-tag.*noindex|x-robots-tag.*none"; then
    CF_BLOCK_SIGNALS+=("x-robots-tag: noindex in HTTP response headers")
  fi

  # Fetch actual body as GPTBot and check for Cloudflare challenge page
  BOT_BODY=$(curl $CURL_OPTS -A "GPTBot/1.2 (+https://openai.com/gptbot)" "$URL" 2>/dev/null || echo "")
  if echo "$BOT_BODY" | grep -qi "challenges.cloudflare.com\|cf-turnstile\|Just a moment"; then
    CF_BLOCK_SIGNALS+=("Cloudflare challenge/CAPTCHA page returned to GPTBot")
  fi

  if [[ ${#CF_BLOCK_SIGNALS[@]} -gt 0 ]]; then
    fail "Cloudflare appears to be blocking AI crawlers:"
    for sig in "${CF_BLOCK_SIGNALS[@]}"; do
      info "$sig"
    done
    info "Fix: Cloudflare dashboard -> Security -> Bots -> disable 'Block AI Scrapers'"
    info "Or: WAF -> Rules -> allow GPTBot/ClaudeBot/PerplexityBot user-agents"
    CF_SCORE=0
  else
    pass "No Cloudflare AI blocking signals detected"
    if echo "$CF_HEADERS_STANDARD" | grep -qi "cloudflare\|cf-ray"; then
      info "Site uses Cloudflare but no AI blocking found (good)"
    fi
  fi
fi

echo ""

# ─────────────────────────────────────────────
# 4. STRUCTURED DATA (schema.org)
# ─────────────────────────────────────────────
echo "4. Structured data (schema.org)"
PAGE_HTML=$(curl $CURL_OPTS "$URL" 2>/dev/null || echo "FETCH_FAILED")

SCHEMA_SCORE=0
if [[ "$PAGE_HTML" == "FETCH_FAILED" ]]; then
  warn "Could not fetch page HTML"
else
  JSONLD_COUNT=$(count_matches 'application/ld.json' "$PAGE_HTML")
  MICRODATA_COUNT=$(count_matches 'itemtype.*schema.org' "$PAGE_HTML")
  OG_COUNT=$(count_matches 'property="og:' "$PAGE_HTML")

  if [[ "$JSONLD_COUNT" -gt 0 ]]; then
    pass "JSON-LD structured data found ($JSONLD_COUNT block(s))"
    SCHEMA_TYPES=$(echo "$PAGE_HTML" | grep -oP '"@type"\s*:\s*"\K[^"]+' | sort -u | head -5 | tr '\n' ', ' | sed 's/,$//')
    [[ -n "$SCHEMA_TYPES" ]] && info "Schema types detected: $SCHEMA_TYPES"
    SCHEMA_SCORE=2
  elif [[ "$MICRODATA_COUNT" -gt 0 ]]; then
    pass "Microdata schema.org markup found ($MICRODATA_COUNT instances)"
    SCHEMA_SCORE=2
  else
    fail "No schema.org structured data found"
    info "Add JSON-LD — helps AI cite your pages accurately"
    info 'Minimal: <script type="application/ld+json">{"@context":"https://schema.org","@type":"WebPage","name":"Title","description":"..."}</script>'
    SCHEMA_SCORE=0
  fi

  if [[ "$OG_COUNT" -gt 0 ]]; then
    info "Open Graph meta tags found ($OG_COUNT) — good for AI context"
  else
    info "No Open Graph tags — consider adding og:title and og:description"
  fi
fi

echo ""

# ─────────────────────────────────────────────
# 5. META TAGS (noindex / noai)
# ─────────────────────────────────────────────
echo "5. Meta tags (noindex / noai directives)"
META_SCORE=2
if [[ "$PAGE_HTML" == "FETCH_FAILED" ]]; then
  warn "Could not check meta tags (page fetch failed)"
  META_SCORE=1
else
  META_ISSUES=()

  # noindex in meta robots tag
  if echo "$PAGE_HTML" | grep -qi 'name="robots"' && echo "$PAGE_HTML" | grep -qi 'noindex'; then
    # Make sure both are in same meta tag (check nearby context)
    ROBOTS_META=$(echo "$PAGE_HTML" | grep -iP '<meta[^>]+robots[^>]+>' | head -3)
    if echo "$ROBOTS_META" | grep -qi 'noindex'; then
      META_ISSUES+=("meta name=robots contains noindex — AI cannot index this page")
    fi
  fi

  # noai directive (emerging standard)
  if echo "$PAGE_HTML" | grep -qi 'noai'; then
    META_ISSUES+=("noai directive found in page")
  fi

  # x-robots-tag from headers (already fetched above)
  if [[ "$CF_HEADERS_STANDARD" != "FETCH_FAILED" ]]; then
    if echo "$CF_HEADERS_STANDARD" | grep -qiP "x-robots-tag.*noindex"; then
      META_ISSUES+=("x-robots-tag: noindex in HTTP headers")
    fi
  fi

  if [[ ${#META_ISSUES[@]} -gt 0 ]]; then
    fail "Restrictive directives found:"
    for issue in "${META_ISSUES[@]}"; do
      info "$issue"
    done
    info "Fix: Remove noindex/noai meta tags if you want AI to index this content"
    META_SCORE=0
  else
    pass "No noindex or noai directives found"
  fi
fi

echo ""

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
TOTAL=$((ROBOTS_SCORE + LLMS_SCORE + CF_SCORE + SCHEMA_SCORE + META_SCORE))
MAX=10

echo "========================================"
echo "  SUMMARY -- $URL"
echo "========================================"

grade_check() {
  local score=$1
  if [[ $score -eq 2 ]]; then echo "PASS"
  elif [[ $score -eq 1 ]]; then echo "WARN"
  else echo "FAIL"
  fi
}

echo "  robots.txt:  $(grade_check $ROBOTS_SCORE)"
echo "  llms.txt:    $(grade_check $LLMS_SCORE)"
echo "  Cloudflare:  $(grade_check $CF_SCORE)"
echo "  Schema.org:  $(grade_check $SCHEMA_SCORE)"
echo "  Meta tags:   $(grade_check $META_SCORE)"
echo ""
echo "  Score: $TOTAL/$MAX"

if [[ $TOTAL -ge 9 ]]; then
  echo "  Grade: EXCELLENT -- AI crawlers can find and cite this site"
elif [[ $TOTAL -ge 7 ]]; then
  echo "  Grade: GOOD -- Minor improvements possible"
elif [[ $TOTAL -ge 5 ]]; then
  echo "  Grade: FAIR -- Some AI crawlers may be blocked or miss content"
else
  echo "  Grade: POOR -- AI crawlers likely blocked or unable to understand content"
fi
echo "========================================"
echo ""
