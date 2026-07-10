#!/usr/bin/env bash
# app-onboarding.sh — Generate complete in-app onboarding copy for a mobile app
# Usage: bash skills/app-onboarding.sh <product-name> [persona] [warm|professional|urgent]
set -euo pipefail

PRODUCT="${1:-}"
PERSONA="${2:-new user}"
TONE="${3:-warm}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [persona] [warm|professional|urgent]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app 'distressed debtor' warm" >&2
  echo "  $0 cleardebt 'first-time filer' professional" >&2
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
  local prompt="$1" max_tokens="${2:-3000}" suffix="${3:-onboarding}"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt")
  HTTP=$(curl -s -o "/tmp/.onboard-resp-${suffix}.json" -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat "/tmp/.onboard-resp-${suffix}.json" >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.onboard-resp-${suffix}.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

echo "Generating app onboarding copy for $PRODUCT (persona: $PERSONA, tone: $TONE)..." >&2

# ── Call 1: Onboarding screens + splash + permissions ────────────────────────
SCREENS_PROMPT="You are a mobile UX copywriter specialising in consumer apps. Write in a $TONE tone for a $PERSONA audience.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Generate the following copy sections. Be specific to this product — do not write generic placeholder text.

---

## 1. SPLASH / LOADING SCREEN

**Tagline:** (under 6 words — the product's promise in a phrase)
**Loading message:** (under 8 words — what the app is doing while loading, encouraging)

---

## 2. ONBOARDING FLOW (4 screens)

For each screen provide exactly:
- **Headline:** (6 words MAX — specific, benefit-led, no jargon)
- **Body:** (20 words MAX — one concrete, human sentence)
- **CTA button:** (2-4 words)
- **Skip link text:** (2-4 words, reassuring not dismissive)
- **Illustration description:** (10-15 words describing what to show — no text in image)

SCREEN 1 — The Problem / Empathy (acknowledge what they're going through)
SCREEN 2 — The Solution / Promise (what this app does for them)
SCREEN 3 — The Process / How It Works (make it feel simple, 3 steps max)
SCREEN 4 — The Proof / Trust (social proof, safety, or credibility signal)

---

## 3. PERMISSIONS PROMPTS

Write the in-app pre-permission dialog (shown BEFORE the OS prompt) for each:

**Camera / Photo Library** (for document scanning / OCR):
- **Headline:** (under 8 words)
- **Body:** (under 25 words — explain exactly WHY the app needs this, user benefit first)
- **Allow button:** (2-3 words)
- **Not now button:** (2-3 words)

**Push Notifications:**
- **Headline:** (under 8 words)
- **Body:** (under 25 words — explain what notifications they'll get and why it helps them)
- **Allow button:** (2-3 words)
- **Not now button:** (2-3 words)

Keep every word purposeful. $TONE tone. This is for a $PERSONA."

# ── Call 2: Empty states + push notifications + rating + errors ───────────────
CONTENT_PROMPT="You are a mobile UX copywriter specialising in consumer apps. Write in a $TONE tone for a $PERSONA audience.

Product: $PRODUCT
Context:
$PRODUCT_DESC

Generate the following copy sections. Be specific to this product — no generic placeholder text.

---

## 4. EMPTY STATES

For each main screen, write what to show when there is no data yet.
Each empty state needs:
- **Illustration description:** (10-15 words — what visual to show)
- **Headline:** (under 6 words — empathetic, not 'No items found')
- **Body:** (under 20 words — what to do next, make it feel easy)
- **CTA button:** (2-4 words — the first action to take)

**Dashboard (no case started):**
**Documents (no files uploaded yet):**
**Checklist (no tasks completed):**

---

## 5. PUSH NOTIFICATION TEMPLATES

Write 6 push notification templates. Each needs:
- **Title:** (under 5 words)
- **Body:** (under 15 words)
- **Deep-link target:** (which screen to open)

TEMPLATE 1 — Welcome (sent immediately after sign-up)
TEMPLATE 2 — Reminder D+1 (user signed up but hasn't started)
TEMPLATE 3 — Document uploaded (confirmation after user uploads a file)
TEMPLATE 4 — Milestone (user completed a major step — celebrate it)
TEMPLATE 5 — Re-engagement D+7 (user hasn't opened app in 7 days)
TEMPLATE 6 — Re-engagement D+30 (user went dormant — final nudge, high urgency)

---

## 6. APP RATING PROMPT

**Timing:** (when to show this — specific trigger event, not 'after 3 uses')
**Headline:** (under 8 words — personal, not 'Rate our app')
**Body:** (under 20 words — make them feel their review genuinely helps)
**Yes button:** (2-4 words)
**No / Not now button:** (2-4 words)

---

## 7. ERROR MESSAGES (human-friendly)

Rewrite these 5 common technical errors as friendly, helpful copy.
Format: **Error situation** → Headline + Body (under 20 words) + Action button

1. No internet connection
2. File upload failed (too large or wrong format)
3. Session expired / logged out
4. Server error / something went wrong on our end
5. Form validation failed (user left required fields blank)

Rule: Never show 'Error 404', stack traces, or technical codes to the user. Always say what to do next.

$TONE tone throughout. This is for a $PERSONA."

echo "  [1/2] Onboarding screens + splash + permissions..." >&2
SCREENS=$(call_claude "$SCREENS_PROMPT" 3000 "screens")

echo "  [2/2] Empty states + notifications + rating + errors..." >&2
CONTENT=$(call_claude "$CONTENT_PROMPT" 3000 "content")

# ── Output ────────────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/app-onboarding-${PRODUCT_LOWER}-${DATE}.md"

{
  echo "# App Onboarding Copy — $PRODUCT"
  echo "Generated: $DATE | Persona: $PERSONA | Tone: $TONE"
  echo
  echo "---"
  echo
  echo "$SCREENS"
  echo
  echo "---"
  echo
  echo "$CONTENT"
} > "$OUTFILE"

# Save to product marketing folder if it exists
if [[ -n "$PRODUCT_DIR" && -d "$PRODUCT_DIR/marketing" ]]; then
  cp "$OUTFILE" "$PRODUCT_DIR/marketing/10-app-onboarding-copy.md"
  echo "Also saved to: $PRODUCT_DIR/marketing/10-app-onboarding-copy.md" >&2
fi

echo
echo "════════════════════════════════════════════════"
echo "  APP ONBOARDING COPY — $PRODUCT"
echo "  Persona: $PERSONA | Tone: $TONE"
echo "════════════════════════════════════════════════"
echo
echo "$SCREENS"
echo
echo "---"
echo
echo "$CONTENT"
echo
echo "════════════════════════════════════════════════"
echo "Saved: $OUTFILE" >&2

rm -f /tmp/.onboard-resp-screens.json /tmp/.onboard-resp-content.json
