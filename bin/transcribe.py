#!/usr/bin/env python3
"""Transcribe an audio file (ogg/oga/mp3/wav/...) to text using faster-whisper.
Reuses the locally cached `base` model. Prints the transcript to stdout.
Usage: transcribe.py <audio-file> [language]
"""
import sys

def main() -> int:
    if len(sys.argv) < 2:
        print("usage: transcribe.py <audio-file> [language]", file=sys.stderr)
        return 2
    audio = sys.argv[1]
    language = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

    import os

    # Validate local file — reject URIs (http://, rtsp://, etc.) and missing paths
    # before loading the model or invoking ffmpeg (prevents SSRF via ffmpeg -i).
    if not os.path.isfile(audio):
        print(f"File not found: {audio}", file=sys.stderr)
        return 1

    # Phone voice notes are often recorded quietly; raw Whisper then drops them or
    # hallucinates ("I'm sorry…" loops). Pre-normalise loudness with ffmpeg so quiet
    # speech is audible to the model. Falls back to the raw file if ffmpeg is missing.
    import shutil, subprocess, tempfile
    norm_path = None
    if shutil.which("ffmpeg"):
        fd, norm_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        rc = subprocess.run(
            ["ffmpeg", "-y", "-i", audio, "-af", "dynaudnorm=f=150:g=15",
             "-ar", "16000", "-ac", "1", norm_path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode
        if rc != 0 or os.path.getsize(norm_path) == 0:
            os.unlink(norm_path)
            norm_path = None
    src = norm_path or audio

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print("faster-whisper not installed. Run: uv pip install faster-whisper", file=sys.stderr)
        return 1

    # int8 on CPU. `medium.en` is markedly more accurate than `small.en` on short/quiet
    # phone voice notes (small.en kept mangling words like "phase"->"phrase"). This box has
    # 16 cores + 15GB free, so medium runs comfortably and stays fully offline/free.
    # Override with env WHISPER_MODEL if a smaller/faster model is ever needed.
    model_name = os.environ.get("WHISPER_MODEL", "medium.en")
    print(f"loading whisper model ({model_name})...", file=sys.stderr, flush=True)
    # Resolve to local cache path to avoid huggingface_hub network check hanging
    import glob, pathlib
    _hf_cache = pathlib.Path.home() / ".cache" / "huggingface" / "hub"
    _safe_name = model_name.replace("/", "--")
    _candidates = sorted(glob.glob(str(_hf_cache / f"models--Systran--faster-whisper-{_safe_name}" / "snapshots" / "*" / "")))
    model_path = _candidates[-1] if _candidates else model_name
    model = WhisperModel(model_path, device="cpu", compute_type="int8")
    segments, _info = model.transcribe(
        src,
        language=language or "en",
        vad_filter=True,
        beam_size=5,                       # a little wider search = fewer misheard words
        condition_on_previous_text=False,  # stop repetition/hallucination loops
    )
    text = "".join(seg.text for seg in segments).strip()
    if norm_path:
        os.unlink(norm_path)

    if not text:
        print("no speech detected", file=sys.stderr)
        return 2

    print(text)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
