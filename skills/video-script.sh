#!/usr/bin/env bash
# video-script.sh — Generate platform-optimized short-form video scripts for brand content
# Usage: bash skills/video-script.sh <product-name> [platform: tiktok|reels|shorts|all] [angle: problem|solution|story|proof|myth] [n-scripts: 1-5]
set -euo pipefail

PRODUCT="${1:-}"
PLATFORM="${2:-all}"
ANGLE="${3:-problem}"
N_SCRIPTS="${4:-1}"

if [[ -z "$PRODUCT" ]]; then
  echo "Usage: $0 <product-name> [tiktok|reels|shorts|all] [problem|solution|story|proof|myth] [1-5]" >&2
  echo "Examples:" >&2
  echo "  $0 bankruptcy-app tiktok myth 2" >&2
  echo "  $0 bankruptcy-app all solution 1" >&2
  echo "  $0 cleardebt reels story 3" >&2
  exit 1
fi

# ── Product context ──────────────────────────────────────────────────────────
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
[[ -z "$PRODUCT_DESC" ]] && PRODUCT_DESC="$PRODUCT (no product context found)"

# ── API setup ────────────────────────────────────────────────────────────────
TOKEN=$(python3 -c "
import json
with open('/home/barry/.claude/.credentials.json') as f:
  d = json.load(f)
print(d.get('claudeAiOauth', {}).get('accessToken') or
      d.get('primaryAccount', {}).get('oauthAccount',{}).get('accessToken',''))
" 2>/dev/null)
[[ -z "$TOKEN" ]] && { echo "ERROR: no API token found" >&2; exit 1; }

# ── Claude call helper ───────────────────────────────────────────────────────
call_claude() {
  local prompt="$1" max_tokens="${2:-3000}"
  local escaped
  escaped=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$prompt")
  HTTP=$(curl -s -o /tmp/.vs-resp.json -w "%{http_code}" http://127.0.0.1:8787/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":$max_tokens,\"messages\":[{\"role\":\"user\",\"content\":$escaped}]}")
  [[ "$HTTP" != "200" ]] && { echo "API error $HTTP" >&2; cat /tmp/.vs-resp.json >&2; return 1; }
  python3 -c "
import json
resp = json.loads(open('/tmp/.vs-resp.json').read())
print(''.join(b['text'] for b in resp.get('content',[]) if b.get('type')=='text'))
"
}

# ── Angle descriptions ───────────────────────────────────────────────────────
angle_desc() {
  case "$1" in
    problem)  echo "Opens with the pain point, agitates it, then reveals the product as relief. Make the viewer feel seen before showing the solution." ;;
    solution) echo 'POV: you found out about X. Benefit-first hook — lead with the outcome, then explain how. The viewer should think \"I need this\" by second 3.' ;;
    story)    echo "Before/after narrative — 3 acts: rock bottom, discovery, transformation. Emotional arc. Real human journey, not a pitch." ;;
    proof)    echo 'Social proof hook — "X people did Y and here is what happened." Data point or testimonial opens, product is the common thread.' ;;
    myth)     echo 'Myth-busting — "You do not need a lawyer to file bankruptcy. Here is why." Challenge a false belief the audience holds, then reveal the truth.' ;;
    *)        echo "Problem-agitate-solve structure. Open with pain, reveal solution." ;;
  esac
}

ANGLE_GUIDE=$(angle_desc "$ANGLE")

# ── Platform specs ───────────────────────────────────────────────────────────
TIKTOK_SPEC="TikTok (30-60 seconds):
- Hook MUST land in first 1 second — one punchy sentence, no intro
- Trending audio suggestion (name a mood/genre, e.g. 'trending lo-fi beat' or 'viral POV audio')
- Text overlay cues at each timestamp — what text appears on screen
- Caption under 150 chars + 5-7 hashtags (mix niche + broad)
- Thumbnail text (cover frame — bold, 5 words max)"

REELS_SPEC="Instagram Reels (15-30 seconds):
- Visual-first: describe each shot (what camera sees) at every timestamp
- 3-act structure: hook / middle / payoff — tight
- Music mood suggestion (e.g. 'uplifting acoustic', 'cinematic swell')
- Caption 100 chars + 5 hashtags
- Thumbnail text (cover frame)"

SHORTS_SPEC="YouTube Shorts (45-60 seconds):
- SEO title suggestion (what to title the Short for discoverability)
- Chapter markers if over 45s (e.g. [0:00] Hook / [0:08] Problem / etc.)
- Thumbnail text (bold 4-6 words, high contrast)
- Caption 200 chars + 3-5 hashtags
- End card call-to-action (subscribe / link in bio / comment)"

# ── Script template ──────────────────────────────────────────────────────────
script_block() {
  local platform_spec="$1"
  cat <<EOF
For each script, output EXACTLY this structure (no extra commentary between scripts):

---
**HOOK** (say this in the first 1-3 seconds):
[The hook line]

**SCRIPT WITH TIMESTAMPS:**
[0:00-0:03] [what you say] | ON SCREEN: [text overlay or visual]
[0:03-0:10] [what you say] | ON SCREEN: [text overlay or visual]
... (continue for full duration)

**AUDIO / MUSIC MOOD:**
[suggestion]

**CAPTION:**
[caption text] [hashtags]

**THUMBNAIL TEXT:**
[5 words max, bold]

**A/B HOOK VARIANTS (2 alternatives to test):**
A) [variant 1]
B) [variant 2]
---
EOF
}

# ── Prompts ──────────────────────────────────────────────────────────────────
build_prompt() {
  local platform_label="$1"
  local platform_spec="$2"
  local n="$3"
  local template
  template=$(script_block "$platform_spec")

  cat <<EOF
You are a short-form video strategist for brand content (NOT UGC — polished, brand-owned style).

Product: $PRODUCT
Product context:
$PRODUCT_DESC

Angle: $ANGLE
Angle guide: $ANGLE_GUIDE

Platform spec:
$platform_spec

Write $n video script(s) for $platform_label. Each must be DIFFERENT (vary hooks, openings, energy).

Rules:
- Brand voice: authoritative, empathetic, clear — NOT salesy or hype-y
- Every hook must be 1 sentence, under 10 words, stops the scroll
- Timestamps must be realistic for the platform duration
- On-screen text: short (3-5 words per overlay) — viewer reads while listening
- Hashtags: platform-appropriate mix of niche (#bankruptcyhelp) and broad (#personalfinance)
- NO filler phrases: "Are you struggling?" / "Have you ever wondered?" — cut them
- Each script self-contained — viewer who has never heard of $PRODUCT understands it

$template

Output $n script(s) now. Separate each with a blank line and "=== SCRIPT [N] ===".
EOF
}

# ── Determine which platforms to run ────────────────────────────────────────
run_tiktok=false
run_reels=false
run_shorts=false

case "$PLATFORM" in
  tiktok)  run_tiktok=true ;;
  reels)   run_reels=true ;;
  shorts)  run_shorts=true ;;
  all)     run_tiktok=true; run_reels=true; run_shorts=true ;;
  *)
    echo "Unknown platform '$PLATFORM'. Use: tiktok|reels|shorts|all" >&2
    exit 1
    ;;
esac

echo "Generating $N_SCRIPTS $PLATFORM video script(s) for $PRODUCT (angle: $ANGLE)..." >&2

# ── Phase 1: TikTok + Reels (parallel call 1) ───────────────────────────────
TIKTOK_SCRIPTS=""
REELS_SCRIPTS=""

if $run_tiktok || $run_reels; then
  # Build combined prompt for call 1
  COMBINED_PLATFORMS=""
  $run_tiktok && COMBINED_PLATFORMS="$COMBINED_PLATFORMS TikTok"
  $run_reels  && COMBINED_PLATFORMS="$COMBINED_PLATFORMS Reels"

  COMBINED_SPEC=""
  $run_tiktok && COMBINED_SPEC="$COMBINED_SPEC
== TIKTOK ==
$TIKTOK_SPEC"
  $run_reels  && COMBINED_SPEC="$COMBINED_SPEC
== REELS ==
$REELS_SPEC"

  PROMPT1=$(build_prompt "$COMBINED_PLATFORMS" "$COMBINED_SPEC" "$N_SCRIPTS")
  echo " [1/2] TikTok/Reels scripts..." >&2
  CALL1_OUT=$(call_claude "$PROMPT1" 4000)
fi

# ── Phase 2: Shorts (call 2) ─────────────────────────────────────────────────
SHORTS_SCRIPTS=""
if $run_shorts; then
  PROMPT2=$(build_prompt "YouTube Shorts" "$SHORTS_SPEC" "$N_SCRIPTS")
  echo " [2/2] Shorts scripts..." >&2
  SHORTS_SCRIPTS=$(call_claude "$PROMPT2" 3000)
fi

# Assign call 1 output
if $run_tiktok || $run_reels; then
  if $run_tiktok && $run_reels; then
    # Split by == TIKTOK == / == REELS == markers if both present
    TIKTOK_SCRIPTS="$CALL1_OUT"
    REELS_SCRIPTS="$CALL1_OUT"
  elif $run_tiktok; then
    TIKTOK_SCRIPTS="$CALL1_OUT"
  else
    REELS_SCRIPTS="$CALL1_OUT"
  fi
fi

# ── Output ───────────────────────────────────────────────────────────────────
DATE=$(date '+%Y-%m-%d')
OUTFILE="/home/barry/projects/obsidian/notes/video-script-${PRODUCT_LOWER}-${PLATFORM}-${DATE}.md"

{
  echo "# Video Scripts — $PRODUCT | $PLATFORM | $ANGLE"
  echo "Generated: $DATE | n=$N_SCRIPTS"
  echo
  echo "---"

  if $run_tiktok; then
    echo "## TikTok Scripts ($N_SCRIPTS)"
    echo
    echo "$TIKTOK_SCRIPTS"
    echo
    echo "---"
  fi

  if $run_reels && ! $run_tiktok; then
    echo "## Reels Scripts ($N_SCRIPTS)"
    echo
    echo "$REELS_SCRIPTS"
    echo
    echo "---"
  fi

  if $run_shorts; then
    echo "## YouTube Shorts Scripts ($N_SCRIPTS)"
    echo
    echo "$SHORTS_SCRIPTS"
    echo
    echo "---"
  fi
} > "$OUTFILE"

# Copy to product marketing folder
MKTG_DIR="${PRODUCT_DIR:-}/marketing"
if [[ -n "${PRODUCT_DIR:-}" && -d "$MKTG_DIR" ]]; then
  cp "$OUTFILE" "$MKTG_DIR/11-video-scripts.md"
  echo "Also saved to: $MKTG_DIR/11-video-scripts.md" >&2
fi

# ── Print to stdout ──────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════"
echo " VIDEO SCRIPTS — $PRODUCT | $PLATFORM | $ANGLE"
echo "════════════════════════════════════════════════"
echo

if $run_tiktok; then
  echo "## TIKTOK ($N_SCRIPTS scripts)"
  echo "$TIKTOK_SCRIPTS"
  echo
  echo "---"
  echo
fi

if $run_reels && ! $run_tiktok; then
  echo "## REELS ($N_SCRIPTS scripts)"
  echo "$REELS_SCRIPTS"
  echo
  echo "---"
  echo
fi

if $run_shorts; then
  echo "## SHORTS ($N_SCRIPTS scripts)"
  echo "$SHORTS_SCRIPTS"
  echo
  echo "---"
  echo
fi

echo "Saved: $OUTFILE" >&2
rm -f /tmp/.vs-resp.json
