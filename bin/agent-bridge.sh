#!/usr/bin/env bash
# Thin wrapper → agent-bridge.py (robust Python implementation).
exec python3 "$(dirname "$0")/agent-bridge.py" "$@"
