#!/usr/bin/env bash
# Transcribe an audio file to text. Usage: transcribe.sh <audio-file> [language]
# Prints the transcript to stdout. Used by the Telegram channel session for voice notes.
set -euo pipefail
DIR="${CLAUDETEAM_ROOT:-$HOME/projects/claudeteam}"
PY="$DIR/.venv-voice/bin/python"
if [ ! -x "$PY" ]; then
  echo "voice env missing: run  uv venv -p 3.12 $DIR/.venv-voice && uv pip install --python $PY faster-whisper" >&2
  exit 1
fi
exec "$PY" "$DIR/bin/transcribe.py" "$@"
