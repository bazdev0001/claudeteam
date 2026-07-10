#!/usr/bin/env bash
# watch-video.sh — Doss's video ingestion pipeline (the lean version of the
# "Autonomous Video Knowledge Pipeline": INGEST -> DISSECT -> CONNECT).
#
# Usage:  bash bin/watch-video.sh <youtube-url | local-file> [max_frames]
#
# It does NOT call any external API. It uses:
#   - yt-dlp   : download (skipped if arg is a local file)
#   - ffmpeg   : pull audio + scene-change keyframes
#   - transcribe.sh (local faster-whisper medium.en) : audio -> text
# Output: a work dir with transcript.txt + frames/*.png + info.txt.
# Doss then READS the transcript and the frames (vision) and writes a
# structured note into the Obsidian vault (the CONNECT step).
set -euo pipefail

SRC="${1:?usage: watch-video.sh <url|file> [max_frames]}"
MAXF="${2:-12}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="/home/barry/projects/claudeteam/.video-out/$STAMP"
mkdir -p "$WORK/frames"

echo ">> work dir: $WORK"

# ---- INGEST -------------------------------------------------------------
if [[ -f "$SRC" ]]; then
  VID="$SRC"
  echo ">> local file: $VID"
  { echo "source: local-file"; echo "path: $SRC"; } > "$WORK/info.txt"
else
  echo ">> downloading: $SRC"
  yt-dlp -f "bv*[height<=720]+ba/b[height<=720]/b" \
         --merge-output-format mp4 \
         -o "$WORK/video.%(ext)s" \
         --print-to-file "%(title)s\n%(channel)s\n%(duration)s\n%(webpage_url)s" "$WORK/info.txt" \
         "$SRC"
  VID="$(ls "$WORK"/video.* | head -1)"
  echo ">> downloaded: $VID"
fi

# ---- DISSECT: audio -> transcript --------------------------------------
echo ">> extracting audio"
ffmpeg -nostdin -y -i "$VID" -vn -ac 1 -ar 16000 "$WORK/audio.wav" >/dev/null 2>&1
echo ">> transcribing (local whisper, no API)"
bash "$HERE/bin/transcribe.sh" "$WORK/audio.wav" > "$WORK/transcript.txt" || true
echo ">> transcript: $(wc -w < "$WORK/transcript.txt") words"

# ---- DISSECT: scene-change keyframes -----------------------------------
echo ">> extracting scene-change frames (up to $MAXF)"
ffmpeg -nostdin -y -i "$VID" \
  -vf "select='gt(scene,0.4)',scale=1024:-1" -vsync vfr \
  -frames:v "$MAXF" "$WORK/frames/scene_%02d.png" >/dev/null 2>&1 || true
# fallback: if scene detection found nothing, sample evenly
if [[ -z "$(ls -A "$WORK/frames" 2>/dev/null)" ]]; then
  DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VID" 2>/dev/null | cut -d. -f1)"
  DUR="${DUR:-60}"; STEP=$(( DUR / MAXF + 1 ))
  ffmpeg -nostdin -y -i "$VID" -vf "fps=1/$STEP,scale=1024:-1" \
    -frames:v "$MAXF" "$WORK/frames/sample_%02d.png" >/dev/null 2>&1 || true
fi
echo ">> frames: $(ls "$WORK/frames" | wc -l)"

echo
echo "DONE. Next (Doss does this in-session):"
echo "  1. Read $WORK/transcript.txt"
echo "  2. Read $WORK/frames/*.png   (vision)"
echo "  3. Write a structured note to the Obsidian vault."
echo "WORK=$WORK"
