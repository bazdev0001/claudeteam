#!/usr/bin/env bash
# ugc-script-gen.sh — Generate UGC video scripts (TikTok/Reels style) for any Apex product
# Usage: bash ugc-script-gen.sh <product-name> [platform: tiktok|reels|youtube-shorts] [duration: 30|60|90]
set -euo pipefail

PRODUCT="${1:-}"
PLATFORM="${2:-tiktok}"
DURATION="${3:-60}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [platform: tiktok|reels|youtube-shorts] [duration: 30|60|90]" >&2
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
      PRODUCT_DESC=$(head -c 800 "$PRODUCT_DIR/$candidate" 2>/dev/null || true)
      break
    fi
  done
fi
[[ -z "$PRODUCT_DESC" ]] && PRODUCT_DESC="$PRODUCT — infer from the product name."

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
PROMPT="You are a UGC (User Generated Content) video scriptwriter for $PLATFORM.

Product: $PRODUCT
Platform: $PLATFORM
Target duration: ${DURATION} seconds
Style: authentic, relatable, first-person POV — like a real user sharing their experience

Product context:
$PRODUCT_DESC

Generate 3 distinct UGC video scripts. Each script must include:

---SCRIPT N---
HOOK (first 3 seconds): <exact words to say — must grab attention instantly>
PROBLEM (5-10 sec): <relatable pain point the viewer feels>
SOLUTION (20-40 sec): <show how the product solves it — specific, visual>
PROOF (10-15 sec): <one concrete result or stat — make it real>
CTA (last 3-5 sec): <clear call to action>

VISUAL DIRECTION:
- Setting: <where to film — bedroom, kitchen, outside, etc.>
- On-screen text: <key words to show as captions>
- B-roll ideas: <screen recordings, close-ups to cut to>

ESTIMATED DURATION: <X seconds>
---

Make each script feel like a different real person, not a corporate ad.
Hook must be scroll-stopping — start mid-action or with a bold claim.
No preamble, output scripts only."

PROMPT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT")

# ── Call Claude via headroom proxy ───────────────────────────────────────────
HTTP_CODE=$(curl -s -o /tmp/.ugc-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
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
  cat /tmp/.ugc-resp.json >&2
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
" "$(cat /tmp/.ugc-resp.json)"
