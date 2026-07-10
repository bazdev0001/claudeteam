#!/usr/bin/env bash
# Text-to-speech for the Telegram channel session.
# Turns text into a Telegram-ready voice note (ogg/opus) using local Piper (free, offline).
# Usage:
#   bin/tg-say.sh "some text"            -> prints path to the generated .ogg
#   echo "some text" | bin/tg-say.sh     -> same, reads stdin
# Then attach that path via the reply tool's `files` arg.
set -euo pipefail
DIR="$HOME/projects/claudeteam"
PY="$DIR/.venv-voice/bin/python"

# Platform guard: Piper venv only available on the mini-PC
if [ ! -x "$PY" ]; then
  echo "tg-say: Piper venv not found at $PY — skipping TTS." >&2
  exit 1
fi

VOICE="$DIR/voices/en_GB-jenny_dioco-medium.onnx"   # female (en_GB jenny); was en_GB-alan (male)

# Verify voice model exists
if [ ! -f "$VOICE" ]; then
  echo "tg-say: voice model not found at $VOICE" >&2
  exit 1
fi

# Softer/slower delivery — the most sensual offline Piper can manage (it has no real emotion control).
LENGTH_SCALE="${TG_SAY_LENGTH_SCALE:-1.15}"
# NOTE: must live OUTSIDE ~/.claude/channels (the reply tool refuses to attach files
# from its own channel-state dir).
OUTDIR="$HOME/projects/claudeteam/.tts-out"
mkdir -p "$OUTDIR"

text="${1:-}"
[ -z "$text" ] && text="$(cat)"
[ -z "${text// }" ] && { echo "tg-say: empty text" >&2; exit 1; }

# Unique-ish name without Date.now(): hash the text.
stamp="$(printf '%s' "$text" | cksum | cut -d' ' -f1)"
wav="$OUTDIR/say-$stamp.wav"
ogg="$OUTDIR/say-$stamp.ogg"

# Ensure wav temp file is cleaned up on any exit path (including set -e aborts)
trap 'rm -f "$wav"' EXIT

# Run Piper — stdout suppressed (output goes to -f $wav), stderr passes through for diagnostics
printf '%s' "$text" | "$PY" -m piper -m "$VOICE" --length-scale "$LENGTH_SCALE" -f "$wav" >/dev/null \
  || { echo "tg-say: piper failed (exit $?)" >&2; exit 1; }

# Verify Piper produced a non-empty WAV
[ -s "$wav" ] || { echo "tg-say: Piper produced empty/missing WAV at $wav" >&2; exit 1; }

# Telegram voice notes want ogg/opus — stdout suppressed, stderr passes through
ffmpeg -nostdin -y -i "$wav" -c:a libopus -b:a 32k "$ogg" >/dev/null \
  || { echo "tg-say: ffmpeg failed (exit $?)" >&2; exit 1; }

# Verify ffmpeg produced a non-empty ogg
[ -s "$ogg" ] || { echo "tg-say: ffmpeg produced empty output at $ogg" >&2; exit 1; }

echo "$ogg"
