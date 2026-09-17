#!/usr/bin/env bash
# minipc-clock-doctor.sh — clock-drift doctor for the mini-PC (WSL2). 2026-07-17.
# Audit 2026-07-17: mini-PC had NO clock doctor (chronyd runs with -x = monitor-only,
# it CANNOT step the WSL clock; WSL2 clocks drift after host sleep/resume).
# Runs every 10 min via minipc-clock-doctor.timer.
#
# Check: offset vs NTP — chronyc tracking first, python3 SNTP fallback.
# |offset| >= threshold (default 2s) -> log + Telegram alert to Barry via Sage's bot
# (max 1/hour). No passwordless sudo here, so it cannot self-correct — the alert
# includes the fix (sudo hwclock -s, or wsl --shutdown from Windows).
# Test hooks: CLOCK_DOCTOR_TEST=1 labels the alert as a test + bypasses the rate
# limit; CLOCK_THRESHOLD_MS overrides the 2000 ms default.

set -uo pipefail
THRESHOLD_MS="${CLOCK_THRESHOLD_MS:-2000}"
ENV_FILE="$HOME/apex/agents/sage/telegram/.env"
CHAT_ID="6062064959"
LOG="$HOME/logs/minipc-clock-doctor.log"
ALERTED="$HOME/.cache/minipc-clock-alerted"
mkdir -p "$HOME/logs" "$HOME/.cache"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# --- measure offset in ms (positive = system clock fast) ---
offset_ms=""
# 1) chronyc tracking: "System time 0.015 seconds fast of NTP time" / "... slow ..."
line=$(chronyc tracking 2>/dev/null | grep -i '^System time') || true
if [ -n "${line:-}" ]; then
  secs=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+' | head -1)
  if [ -n "$secs" ]; then
    offset_ms=$(awk -v s="$secs" 'BEGIN{printf "%d", s*1000}')
    echo "$line" | grep -qi slow && offset_ms=$(( -offset_ms ))
  fi
fi
# 2) fallback: raw SNTP query (stdlib only)
if [ -z "$offset_ms" ]; then
  offset_ms=$(python3 - <<'PY' 2>/dev/null
import socket, struct, sys, time
def q(host):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(5)
    t0 = time.time(); s.sendto(b'\x1b' + 47*b'\0', (host, 123))
    d, _ = s.recvfrom(48); t3 = time.time(); s.close()
    w = struct.unpack('!12I', d)
    ts = lambda i: w[i] - 2208988800 + w[i+1] / 2**32
    return ((ts(8)-t0) + (ts(10)-t3)) / 2   # server ahead => local slow => negative "fast"
for h in ('time.cloudflare.com', 'time.google.com', 'pool.ntp.org'):
    try:
        print(int(round(-q(h)*1000))); sys.exit(0)   # positive = local clock fast
    except Exception:
        pass
sys.exit(1)
PY
) || offset_ms=""
fi

if [ -z "$offset_ms" ]; then
  log "ERROR — could not measure clock offset (chronyc and SNTP both failed)"
  exit 0
fi

abs_ms=${offset_ms#-}
if [ "$abs_ms" -lt "$THRESHOLD_MS" ] && [ -z "${CLOCK_DOCTOR_TEST:-}" ]; then
  [ -f "$ALERTED" ] && { rm -f "$ALERTED"; log "RECOVERED — offset ${offset_ms}ms below ${THRESHOLD_MS}ms"; }
  log "OK — offset ${offset_ms}ms (threshold ${THRESHOLD_MS}ms)"
  exit 0
fi

log "FAIL — clock offset ${offset_ms}ms >= ${THRESHOLD_MS}ms"
# rate limit: 1 alert/hour (test mode bypasses)
last=$(stat -c %Y "$ALERTED" 2>/dev/null || echo 0)
now=$(date +%s)
if [ -z "${CLOCK_DOCTOR_TEST:-}" ] && (( now - last < 3600 )); then
  log "alert suppressed (rate limit 1/h)"
  exit 0
fi
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null || true
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then log "alert FAILED — no bot token in $ENV_FILE"; exit 0; fi
label=""; [ -n "${CLOCK_DOCTOR_TEST:-}" ] && label="[TEST] "
curl -sf --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  --data-urlencode text="${label}[minipc-clock-doctor] mini-PC (WSL) clock is ${offset_ms}ms off NTP (threshold ${THRESHOLD_MS}ms). chronyd runs monitor-only (-x) and cannot fix this. Fix: in WSL 'sudo hwclock -s', or from Windows 'wsl --shutdown' and reopen." \
  >/dev/null 2>&1 && { touch "$ALERTED"; log "alert sent"; } || log "alert send FAILED"
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
