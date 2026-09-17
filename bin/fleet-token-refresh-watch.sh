#!/usr/bin/env bash
# Item 4: OAuth token refresh watch — tighten threshold, log every attempt's outcome
# Problem: token expiration not caught until API call fails (mid-session).
# Solution: proactive watch on ~/.claude/credentials or token cache, detect staleness.
# Log every refresh attempt: timestamp, token type, success/failure, retry count.
#
# Deploy: timer every 30 min (fleet-token-refresh.timer)
# Watch: /tmp/token-refresh.log for patterns of repeated failures = credential issue

set -euo pipefail

TOKEN_LOG="/tmp/token-refresh.log"
# Claude Code stores OAuth credentials here and refreshes them itself on use;
# this watcher only detects staleness/absence — it cannot refresh externally.
TOKEN_CACHE="$HOME/.claude/.credentials.json"
REFRESH_THRESHOLD=$((60 * 60 * 24))  # 24h without a rewrite on an always-on box = suspicious

log_token_event() {
  local event="$1" token_type="${2:-anthropic}" status="${3:-unknown}" retry_count="${4:-0}"
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] event=$event type=$token_type status=$status retry_count=$retry_count"
  } >> "$TOKEN_LOG"
}

check_token_age() {
  if [ ! -f "$TOKEN_CACHE" ]; then
    log_token_event "check_missing" "anthropic" "no_cache"
    return 1
  fi
  local mtime=$(stat -c %Y "$TOKEN_CACHE" 2>/dev/null || echo 0)
  local now=$(date +%s)
  local age=$((now - mtime))

  if [ "$age" -gt "$REFRESH_THRESHOLD" ]; then
    log_token_event "check_stale" "anthropic" "age_${age}s" 0
    return 1
  fi
  log_token_event "check_ok" "anthropic" "age_${age}s" 0
  return 0
}

if [ ! -f "$TOKEN_CACHE" ]; then
  echo "Credentials file missing ($TOKEN_CACHE) — Claude Code auth is broken. Check $TOKEN_LOG."
  exit 1
fi

if check_token_age; then
  echo "Token check OK"
else
  # Stale mtime alone isn't fatal (refresh happens lazily on use) — log it so
  # repeated stale checks in $TOKEN_LOG surface a real credential problem.
  echo "Token cache stale — watching. See $TOKEN_LOG."
fi
