#!/usr/bin/env bash
# Inner exec for the mini-PC's always-on Claude Code Remote Control session.
# Run via `script` (supplies the pty) from claude-remote-control.service.
#
# Before this existed the RC session was hand-started from a Windows terminal, so its
# parent was /init and it died on every WSL restart. Supervising it here makes it
# survive reboots the same way the Telegram/Discord channel nodes do.
set -euo pipefail

# Route through headroom proxy if running (context compression) — same as the channel nodes.
# MUST be time-bounded: when nothing listens on 8787, WSL2 drops the SYN instead of
# refusing it, so a bare `curl -sf` hangs forever and claude never starts.
if curl -sf --connect-timeout 2 --max-time 3 http://127.0.0.1:8787/health >/dev/null 2>&1; then
  export ANTHROPIC_BASE_URL=http://127.0.0.1:8787
fi

exec claude --remote-control
