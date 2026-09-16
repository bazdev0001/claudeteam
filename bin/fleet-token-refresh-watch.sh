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
CREDENTIALS="$HOME/.claude/credentials"
TOKEN_CACHE="$HOME/.claude/auth/tokens.json"
REFRESH_THRESHOLD=$((60 * 60 * 8))  # 8 hours — refresh if older

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

attempt_refresh() {
  local retry=0
  local max_retries=3

  while [ $retry -lt $max_retries ]; do
    log_token_event "refresh_attempt" "anthropic" "start" "$retry"

    if curl -sf --connect-timeout 3 --max-time 5 \
         -X POST "https://api.anthropic.com/v1/auth/refresh" \
         -H "Content-Type: application/json" \
         >/dev/null 2>&1; then
      log_token_event "refresh_success" "anthropic" "ok" "$retry"
      return 0
    fi

    retry=$((retry + 1))
    [ $retry -lt $max_retries ] && sleep 5
  done

  log_token_event "refresh_failed" "anthropic" "exhausted" "$max_retries"
  return 1
}

check_token_age || attempt_refresh || {
  echo "Token refresh failed — credential issue detected. Check $TOKEN_LOG."
  exit 1
}

echo "Token check OK"
