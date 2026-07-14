#!/usr/bin/env bash
# Permanent daily fleet report (OS-level, systemd-driven — survives restarts forever).
# Generates an intelligent report with a headless `claude -p` run, then pushes it to
# Barry's Telegram chat via the Bot API. Used by daily-attack-plan / daily-eod-capture timers.
#   Usage: daily-report.sh plan|eod
set -euo pipefail

KIND="${1:?usage: daily-report.sh plan|eod}"
PROJ="$HOME/projects/claudeteam"
VAULT="$HOME/projects/obsidian"
CHAT_ID="6062064959"
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.hermes/node/bin:$PATH"

# Bot token (same one the channel session uses).
# shellcheck disable=SC1091
source "$HOME/apex/agents/athena/telegram/.env"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN missing in agents/athena/telegram/.env}"

cd "$PROJ"

case "$KIND" in
  plan)
    PROMPT="Generate the 6am ATTACK PLAN for Barry's trading fleet. Gather real data with your tools: which stock + crypto books are active, overnight crypto positions/state, setups/watchlist for the day, key risk notes. Stocks run at the 1pm PT close. Write it SHORT for reading on a phone: concrete details first, then a 2-line summary at the very end. Output ONLY the message text to send — no preamble, no markdown headers, no commentary."
    ;;
  eod)
    PROMPT="Generate the 9pm END-OF-DAY CAPTURE for Barry's trading fleet. Gather real data with your tools: today's stock fills + P&L after the 1pm PT close, crypto fills/stop-outs/rejects, and equity per book vs \$1,000 inception. Write it SHORT for reading on a phone: concrete details first, then a 2-line summary at the very end. Output ONLY the message text to send — no preamble, no markdown headers, no commentary."
    ;;
  *) echo "unknown kind: $KIND" >&2; exit 2 ;;
esac

# Headless generation. Skip permissions (non-interactive, same as the channel service).
REPORT="$(claude -p "$PROMPT" --dangerously-skip-permissions 2>/dev/null || true)"
[ -z "${REPORT// }" ] && REPORT="[$KIND report] generation returned empty at $(date '+%F %H:%M'). Check daily-report.sh / claude CLI."

# Telegram caps a single message at 4096 chars.
REPORT="${REPORT:0:4000}"

curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${REPORT}" >/dev/null

# End-of-day report is also logged to the durable journal.
if [ "$KIND" = "eod" ]; then
  J="$VAULT/journal/$(date +%F).md"
  { echo; echo "## 9pm EOD capture (auto, systemd)"; echo "$REPORT"; } >> "$J"
fi
