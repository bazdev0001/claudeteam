#!/usr/bin/env bash
# WRITE-side shared-brain hook entrypoint. Wired to Stop / PreCompact / SessionEnd.
# Receives the hook JSON payload on stdin and hands it to flush-session.py, which appends
# the not-yet-flushed turns to <vault>/<node>/discussions/<date>.md. Deterministic, no model calls.
# Never block the session: always exit 0.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$DIR/flush-session.py" 2>>"$HOME/.cache/flush-session.err" || true
exit 0
