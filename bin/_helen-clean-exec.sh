#!/usr/bin/env bash
set -euo pipefail
export BAZMENT_AGENT="helen"
SOUL="$HOME/.claude/helen-soul.md"
ARGS=()
[ -f "$SOUL" ] && ARGS=(--append-system-prompt "$(cat "$SOUL")")
HANDOFF="$HOME/bazment/obsidian/helen-handoff.md"
[ -f "$HANDOFF" ] && ARGS+=(--append-system-prompt "$(printf '\n\n## CONTEXT FROM PREVIOUS SESSION\n'; cat "$HANDOFF")")
exec "/home/apex/.local/share/claude/versions/2.1.178" --dangerously-skip-permissions   --model claude-fable-5   --channels plugin:telegram@claude-plugins-official   "${ARGS[@]}"
