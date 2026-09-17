#!/usr/bin/env bash
# Item 3: Duplicate-poller / shared plugin cache isolation (ISS-008/009 class)
# Problem: both Sage and Athena load the same Claude plugins from ~/.claude/plugins/cache.
# If one node's poller opens duplicate sockets or plugin state conflicts, both nodes see it.
# Solution: isolate each node's plugin cache via CLAUDE_PLUGINS_DIR env var.
#
# Deploy: set CLAUDE_PLUGINS_DIR in each node's systemd service (sage/athena separately).
# Watch: monitor for plugin.json lock contention, socket reuse, cache corruption.
#
# Status: Recommended config change (no code fix, envvar-based isolation).

set -euo pipefail

NODE="${1:-all}"  # "sage", "athena", or "all"
BASE_PLUGIN_CACHE="$HOME/.claude/plugins/cache"
SAGE_CACHE="$HOME/apex/agents/sage/.claude/plugins"
ATHENA_CACHE="$HOME/apex/agents/athena/.claude/plugins"

log() { echo "[$(date +%H:%M:%S)] $*"; }

if [[ "$NODE" == "sage" ]] || [[ "$NODE" == "all" ]]; then
  log "Isolating Sage plugin cache..."
  mkdir -p "$SAGE_CACHE"
  if [ -d "$BASE_PLUGIN_CACHE" ]; then
    cp -r "$BASE_PLUGIN_CACHE"/* "$SAGE_CACHE/" 2>/dev/null || true
  fi
  log "Sage cache: $SAGE_CACHE"
  # Recommend: add to claudeteam-channel-tc2.service:
  # Environment="CLAUDE_PLUGINS_DIR=$SAGE_CACHE"
fi

if [[ "$NODE" == "athena" ]] || [[ "$NODE" == "all" ]]; then
  log "Isolating Athena plugin cache..."
  mkdir -p "$ATHENA_CACHE"
  if [ -d "$BASE_PLUGIN_CACHE" ]; then
    cp -r "$BASE_PLUGIN_CACHE"/* "$ATHENA_CACHE/" 2>/dev/null || true
  fi
  log "Athena cache: $ATHENA_CACHE"
  # Recommend: add to claudeteam-channel.service:
  # Environment="CLAUDE_PLUGINS_DIR=$ATHENA_CACHE"
fi

log "Plugin cache isolation recommended. Requires systemd service restart to take effect."
