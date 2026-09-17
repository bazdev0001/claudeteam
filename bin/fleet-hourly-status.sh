#!/usr/bin/env bash
# fleet-hourly-status — Telegram health report from each agent's own bot.
# Schedule lives in fleet-hourly-status.timer: 06:00 + 21:00 PT only (Barry, 2026-07-24).
# Tokens are read from each agent's canonical .env (never hardcoded here).
set -u
CHAT=6062064959
APP=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice

bridge_pid() { # $1 = unit
  local pid
  for pid in $(cat "$APP/$1/cgroup.procs" 2>/dev/null); do
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "telegram.*start" && { echo "$pid"; return; }
  done
}

report() { # $1=name $2=unit $3=env-file $4=optional extra line
  local name=$1 unit=$2 envf=$3 extra=${4:-} tok active since pid mem watch
  tok=$(grep -o 'TELEGRAM_BOT_TOKEN=.*' "$envf" | cut -d= -f2)
  [ -z "$tok" ] && return
  active=$(systemctl --user is-active "$unit" 2>/dev/null)
  since=$(systemctl --user show "$unit" --property=ActiveEnterTimestamp --value 2>/dev/null)
  pid=$(bridge_pid "$unit")
  mem=$(systemctl --user show "$unit" --property=MemoryCurrent --value 2>/dev/null | awk '{printf "%.0fM", $1/1048576}')
  watch=$(grep -c "$name" /tmp/tc-watchdog.log 2>/dev/null || echo 0)
  local b="✅ bridge up (pid $pid)"; [ -z "$pid" ] && b="❌ BRIDGE DOWN"
  curl -sf "https://api.telegram.org/bot$tok/sendMessage" \
    --data-urlencode chat_id=$CHAT \
    --data-urlencode "text=📊 $name status report ($(date '+%H:%M'))
service: $active (since $since)
telegram: $b
memory: $mem${extra:+
$extra}" | python3 -c "import json,sys; r=json.load(sys.stdin); print('$name delivery:', 'ok' if r.get('ok') else 'FAILED '+str(r))"
}

# Helen's last probe result (helen-qa-monitor runs every 5 min, log-only) rides
# along in Sage's report — Barry gets Helen status ONLY here, twice daily.
helen_line="Helen (VPS): $(cat "$HOME/.cache/helen-qa-status" 2>/dev/null || echo 'no probe data')"
report "Sage"   "claudeteam-channel-tc2.service" "/home/barry/apex/agents/sage/telegram/.env" "$helen_line"
report "Athena" "claudeteam-channel.service"     "/home/barry/apex/agents/athena/telegram/.env"
