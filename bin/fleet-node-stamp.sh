#!/usr/bin/env bash
# fleet-node-stamp.sh <inbound|reply|activity> — hook helper, node-scoped activity stamps.
#
# Called from hooks in the SHARED ~/.claude/settings.json, which both Sage and Athena load.
# The pre-existing hooks touched a hardcoded `~/.cache/tc2-last-inbound` / `-last-reply`, so
# Athena's traffic stamped Sage's files and vice versa (verified 2026-09-15). This script
# instead resolves the node from TELEGRAM_STATE_DIR — set per-node by each channel unit and
# inherited by every hook — and writes only that node's stamps under ~/.cache/fleet/<node>/.
#
# Stamps written:
#   last-inbound   UserPromptSubmit   — a message entered this node's session
#   last-reply     PostToolUse(reply) — this node actually called the channel reply tool
#   last-activity  PostToolUse(any)   — this node ran any tool (i.e. is making progress)
#
# Fire-and-forget: never blocks, never fails a hook, exits 0 on every path.

set -uo pipefail
KIND="${1:-}"
case "$KIND" in
  inbound|reply|activity) ;;
  *) exit 0 ;;
esac

LIB="$HOME/projects/claudeteam/bin/fleet-node-lib.sh"
[ -r "$LIB" ] || exit 0
# shellcheck disable=SC1090
. "$LIB" 2>/dev/null || exit 0

# Only sessions that ARE a channel node have this set; ad-hoc sessions are ignored on purpose.
[ -n "${TELEGRAM_STATE_DIR:-}" ] || exit 0
NODE=$(fleet_node_for_statedir "$TELEGRAM_STATE_DIR" 2>/dev/null) || exit 0
[ -n "$NODE" ] || exit 0

DIR=$(fleet_stamp_dir "$NODE") || exit 0
touch "$DIR/last-$KIND" 2>/dev/null || true

# A reply also counts as activity — keeps the "is it making progress" signal honest for a
# node whose only tool call in a turn is the reply itself.
[ "$KIND" = "reply" ] && touch "$DIR/last-activity" 2>/dev/null

exit 0
