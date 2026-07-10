#!/usr/bin/env bash
# social-post-gen.sh — Generate Instagram / Twitter / LinkedIn posts for an Apex product
# Usage: bash social-post-gen.sh <product-name> [audience] [tone: professional|casual|hype]
set -euo pipefail

PRODUCT="${1:-}"
AUDIENCE="${2:-general consumers}"
TONE="${3:-professional}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [audience] [tone: professional|casual|hype]" >&2
  exit 1
fi

# ── Resolve product description ──────────────────────────────────────────────
APEX_DIR="/home/barry/apex/projects"
PRODUCT_LOWER=$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]')

# Try exact match, then case-insensitive folder scan
PRODUCT_DIR=""
if [[ -d "$APEX_DIR/$PRODUCT" ]]; then
  PRODUCT_DIR="$APEX_DIR/$PRODUCT"
elif [[ -d "$APEX_DIR/$PRODUCT_LOWER" ]]; then
  PRODUCT_DIR="$APEX_DIR/$PRODUCT_LOWER"
else
  # fuzzy: find a dir whose name contains the product token
  MATCH=$(find "$APEX_DIR" -maxdepth 1 -type d -iname "*${PRODUCT_LOWER}*" | head -1)
  [[ -n "$MATCH" ]] && PRODUCT_DIR="$MATCH"
fi

PRODUCT_DESC=""
if [[ -n "$PRODUCT_DIR" ]]; then
  for candidate in DESIGN.md README.md PRD.md; do
    if [[ -f "$PRODUCT_DIR/$candidate" ]]; then
      # Pull first 800 chars — enough context, not too many tokens
      PRODUCT_DESC=$(head -c 800 "$PRODUCT_DIR/$candidate" 2>/dev/null || true)
      break
    fi
  done
fi

if [[ -z "$PRODUCT_DESC" ]]; then
  PRODUCT_DESC="$PRODUCT — no description file found; infer from the product name."
fi

# ── Extract bearer token ─────────────────────────────────────────────────────
TOKEN=$(python3 -c "
import json, sys
with open('/home/barry/.claude/.credentials.json') as f:
    d = json.load(f)
# Support multiple credential shapes
tok = (d.get('claudeAiOauth') or {}).get('accessToken') \
   or (d.get('primaryAccount') or {}).get('oauthAccount',{}).get('accessToken') \
   or d.get('oauth_token') \
   or next(iter(d.values())) if d else ''
print(tok)
" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Could not extract bearer token from ~/.claude/.credentials.json" >&2
  exit 1
fi

# ── Build prompt ─────────────────────────────────────────────────────────────
PROMPT="You are a social media copywriter for Apex, a portfolio of consumer apps.

Product: $PRODUCT
Target audience: $AUDIENCE
Tone: $TONE

Product context:
$PRODUCT_DESC

Generate exactly 3 posts per platform, separated clearly.

## INSTAGRAM (3 posts)
Each post: 150-220 words, emoji-friendly, ends with 10-15 relevant hashtags on a new line.

## TWITTER/X (3 posts)
Each post: strictly under 280 characters, punchy hook, no hashtag spam (max 2 hashtags).

## LINKEDIN (3 posts)
Each post: 120-180 words, professional tone, value-focused, ends with 3-5 hashtags.

Format each post as:
[Platform] Post N:
<post text>
---

Do not add preamble or closing remarks — output the posts only."

# Escape for JSON
PROMPT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT")

# ── Call Claude via headroom proxy ───────────────────────────────────────────
call_api() {
  local model="$1"
  curl -s -o /tmp/.social-post-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{
      \"model\": \"$model\",
      \"max_tokens\": 2000,
      \"messages\": [{\"role\": \"user\", \"content\": $PROMPT_JSON}]
    }"
}

# Try sonnet first, fall back to haiku on rate limit
HTTP_CODE=$(call_api "claude-haiku-4-5-20251001")
if [[ "$HTTP_CODE" == "429" ]]; then
  >&2 echo "Sonnet rate-limited, falling back to haiku..."
  HTTP_CODE=$(call_api "claude-haiku-4-5")
fi

if [[ "$HTTP_CODE" != "200" ]]; then
  >&2 echo "API error HTTP $HTTP_CODE"
  cat /tmp/.social-post-resp.json >&2
  exit 1
fi

RESPONSE=$(cat /tmp/.social-post-resp.json)

# ── Extract and print text ───────────────────────────────────────────────────
python3 -c "
import json, sys
resp = json.loads(sys.argv[1])
if 'error' in resp:
    print('API ERROR:', resp['error'], file=sys.stderr)
    sys.exit(1)
content = resp.get('content', [])
for block in content:
    if block.get('type') == 'text':
        print(block['text'])
" "$RESPONSE"
