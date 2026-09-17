#!/usr/bin/env bash
# answer-monitor — message-IN ⇄ successful send-OUT pairing detector (rules.md #22).
#
# Barry's hard rule (2026-07-17): an agent is NORMAL only if every inbound channel
# message produces a SUCCESSFUL reply-tool send within 5 minutes. Sockets up,
# service active, bridge alive — none of that counts if the answer never went out.
# tc-bridge-guardian watches the transport; THIS watches the conversation.
#
# How it works (per agent, every 60s):
#   1. service cgroup -> claude PID (cmdline contains --channels)
#   2. ~/.claude/sessions/<pid>.json -> live sessionId  (registry maintained by
#      Claude Code itself; re-read every sweep so session rotations are followed)
#   3. transcript = ~/.claude/projects/<cwd-slug>/<sessionId>.jsonl
#      (created lazily on first message — absent file = zero traffic = healthy)
#   4. incremental JSONL scan from saved byte offset (complete lines only):
#        INBOUND  = queue-operation enqueue OR non-sidechain user entry whose
#                   content starts with '<channel source=' (dedup chat_id+message_id;
#                   queue-op is counted too so a wedged session that only ENQUEUES
#                   and never prompts still trips the monitor)
#        OUTBOUND = assistant tool_use  mcp__plugin_*__reply  followed by a
#                   tool_result with no is_error  (reacts/edits do NOT count)
#      A successful reply clears every pending inbound that arrived before it.
#   5. pending inbound older than DEADLINE (300s) -> MISS: journal line, Discord
#      alert to #software (NEVER Barry's Telegram — rules), restart the channel
#      service (cooldown so one miss can't restart-loop).
#
# State:  ~/apex/monitoring/answer-monitor/<agent>.state.json  (session/offset/pending)
# Stats:  ~/apex/monitoring/answer-stats/<YYYY-MM-DD>-<agent>.json  (daily proof report)
# Dry run: ANSWER_MONITOR_DRY_RUN=1 -> detect + log + alert-log only, no restarts/posts.
#
# VPS rollout note: only NODES + CG_BASE + DISCORD_ENV are host-specific. Helen's
# transcripts follow the same schema; deploy with her unit name + cwd slug tomorrow.

set -uo pipefail

CG_BASE="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice"
STATE_DIR="$HOME/apex/monitoring/answer-monitor"
STATS_DIR="$HOME/apex/monitoring/answer-stats"
HEARTBEAT="$HOME/logs/answer-monitor.log"
INTERVAL=60
DEADLINE=300           # seconds an inbound may wait for a successful reply send
COOLDOWN_SWEEPS=10     # sweeps to skip a node after we restart it (600s)
BOOT_GRACE=240         # never restart a service younger than this (mid-boot)
DISCORD_ENV="$HOME/apex/agents/sage/discord/.env"
DISCORD_CHANNEL="1519232254600151083"   # #software
DRY_RUN="${ANSWER_MONITOR_DRY_RUN:-0}"

# agent key | systemd unit
NODES=(
  "athena-telegram|claudeteam-channel.service"
  "sage-telegram|claudeteam-channel-tc2.service"
  "sage-discord|claudeteam-channel-discord-sage.service"
  "athena-discord|claudeteam-channel-discord-athena.service"
)

mkdir -p "$STATE_DIR" "$STATS_DIR" "$HOME/logs"

log_beat()    { echo "[$(date '+%F %H:%M:%S')] $*" >> "$HEARTBEAT"; }
log_journal() { echo "[$(date +%H:%M:%S)] $*" >> "/home/barry/projects/obsidian/journal/$(date +%Y-%m-%d).md"; }

post_discord() {  # $1 = message
  local token
  token=$(grep '^DISCORD_BOT_TOKEN=' "$DISCORD_ENV" 2>/dev/null | cut -d= -f2-)
  [[ -n "$token" ]] || { log_beat "alert NOT sent (no discord token)"; return 1; }
  curl -s --max-time 10 "https://discord.com/api/v10/channels/${DISCORD_CHANNEL}/messages" \
    -H "Authorization: Bot ${token}" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$1")" \
    >/dev/null 2>&1
}

# One python sweep scans all agents; prints action lines:
#   MISS|<unit>|<agent>|<message_id>|<age_s>
sweep() {
python3 - "$CG_BASE" "$STATE_DIR" "$STATS_DIR" "$DEADLINE" "${NODES[@]}" <<'PYEOF'
import json, os, re, sys, time, datetime

cg_base, state_dir, stats_dir, deadline = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
nodes = [n.split('|') for n in sys.argv[5:]]
home = os.path.expanduser('~')
now = time.time()

def tag_ts(content):
    m = re.search(r'\bts="([^"]+)"', content[:600])
    if not m: return None
    try:
        return datetime.datetime.fromisoformat(m.group(1).replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None

def entry_ts(d):
    t = d.get('timestamp')
    if not t: return None
    try:
        return datetime.datetime.fromisoformat(t.replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None

def key_of(content):
    cid = re.search(r'\bchat_id="([^"]+)"', content[:600])
    mid = re.search(r'\bmessage_id="([^"]+)"', content[:600])
    return f"{cid.group(1) if cid else '?'}:{mid.group(1) if mid else '?'}"

def find_session(unit):
    """service cgroup -> claude pid -> (sessionId, transcript path) or None"""
    try:
        pids = open(f'{cg_base}/{unit}/cgroup.procs').read().split()
    except OSError:
        return None
    for pid in pids:
        try:
            cmd = open(f'/proc/{pid}/cmdline', 'rb').read().decode('utf-8', 'replace')
        except OSError:
            continue
        if '--channels' not in cmd or 'claude' not in cmd.split('\0', 1)[0]:
            continue
        try:
            reg = json.load(open(f'{home}/.claude/sessions/{pid}.json'))
        except (OSError, ValueError):
            continue
        sid, cwd = reg.get('sessionId'), reg.get('cwd', '')
        if not sid: continue
        slug = re.sub(r'[^A-Za-z0-9]', '-', cwd)
        return sid, f'{home}/.claude/projects/{slug}/{sid}.jsonl'
    return None

def bump(stats_path, field, inc=1, rt=None):
    try:
        s = json.load(open(stats_path))
    except (OSError, ValueError):
        s = {'inbound': 0, 'answered': 0, 'answered_in_time': 0, 'misses': 0, 'sum_rt_s': 0.0}
    s[field] = s.get(field, 0) + inc
    if rt is not None:
        s['sum_rt_s'] = round(s.get('sum_rt_s', 0.0) + rt, 1)
    if s.get('answered'):
        s['mean_response_s'] = round(s['sum_rt_s'] / s['answered'], 1)
    tmp = stats_path + '.tmp'
    json.dump(s, open(tmp, 'w'), indent=1)
    os.replace(tmp, stats_path)

for agent, unit in nodes:
    live = find_session(unit)
    state_path = f'{state_dir}/{agent}.state.json'
    try:
        state = json.load(open(state_path))
    except (OSError, ValueError):
        state = {'session': None, 'offset': 0, 'pending': []}
    if live is None:
        continue                      # no claude proc: guardian's problem, not ours
    sid, transcript = live
    if state.get('session') != sid:
        state = {'session': sid, 'offset': 0, 'pending': []}
    if not os.path.exists(transcript):
        # lazily created on first message -> no traffic yet this session
        json.dump(state, open(state_path, 'w')); continue

    pending = {p['key']: p for p in state.get('pending', [])}
    # reply tool_use ids persist across sweeps: a tool_use and its tool_result can
    # land either side of a sweep boundary (send in flight during the sweep)
    reply_uses = dict.fromkeys(state.get('reply_uses', []), True)
    offset = state.get('offset', 0)
    size = os.path.getsize(transcript)
    if offset > size: offset = 0      # truncated/rewritten defensively
    with open(transcript, 'rb') as f:
        f.seek(offset)
        buf = f.read()
    # only complete lines; leave partial tail for next sweep
    last_nl = buf.rfind(b'\n')
    if last_nl < 0:
        buf = b''
    else:
        offset += last_nl + 1
        buf = buf[:last_nl]

    def date_of(ts):
        return datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d')

    for raw in buf.split(b'\n'):
        if not raw.strip(): continue
        try:
            d = json.loads(raw)
        except ValueError:
            continue
        t = d.get('type')
        msg = d.get('message') or {}
        c = msg.get('content')
        # -------- inbound: queued channel message --------
        if t == 'queue-operation' and isinstance(d.get('content'), str) \
                and d['content'].startswith('<channel source='):
            ts = tag_ts(d['content']) or entry_ts(d) or now
            k = key_of(d['content'])
            if k not in pending:
                pending[k] = {'key': k, 'ts': ts, 'reported': False}
                bump(f'{stats_dir}/{date_of(ts)}-{agent}.json', 'inbound')
        # -------- inbound: prompt-submitted channel message --------
        elif t == 'user' and isinstance(c, str) and c.startswith('<channel source=') \
                and not d.get('isSidechain'):
            ts = tag_ts(c) or entry_ts(d) or now
            k = key_of(c)
            if k not in pending:
                pending[k] = {'key': k, 'ts': ts, 'reported': False}
                bump(f'{stats_dir}/{date_of(ts)}-{agent}.json', 'inbound')
        # -------- outbound: reply tool call --------
        elif t == 'assistant' and isinstance(c, list):
            for b in c:
                if b.get('type') == 'tool_use' and \
                        re.fullmatch(r'mcp__plugin_\w+__reply', b.get('name', '')):
                    reply_uses[b['id']] = True
        # -------- outbound: reply tool result --------
        elif t == 'user' and isinstance(c, list):
            for b in c:
                if b.get('type') == 'tool_result' and b.get('tool_use_id') in reply_uses \
                        and not b.get('is_error'):
                    rts = entry_ts(d) or now
                    for k in [k for k, p in pending.items() if p['ts'] <= rts]:
                        rt = rts - pending[k]['ts']
                        sp = f"{stats_dir}/{date_of(pending[k]['ts'])}-{agent}.json"
                        bump(sp, 'answered', rt=rt)
                        if rt <= deadline:
                            bump(sp, 'answered_in_time')
                        del pending[k]

    # -------- deadline check --------
    for k, p in list(pending.items()):
        age = now - p['ts']
        if age > deadline and not p['reported']:
            mid = k.split(':', 1)[1]
            print(f'MISS|{unit}|{agent}|{mid}|{int(age)}')
            bump(f"{stats_dir}/{date_of(p['ts'])}-{agent}.json", 'misses')
            del pending[k]            # reported once; don't re-fire or count as answered

    state['offset'] = offset
    state['pending'] = list(pending.values())
    state['reply_uses'] = list(reply_uses.keys())[-50:]   # keep recent only
    tmp = state_path + '.tmp'
    json.dump(state, open(tmp, 'w'))
    os.replace(tmp, state_path)
PYEOF
}

declare -A COOLDOWN
for entry in "${NODES[@]}"; do COOLDOWN["${entry#*|}"]=0; done
SWEEP_N=0

[[ "$DRY_RUN" == "1" ]] || log_journal "📨 answer-monitor started (sweep ${INTERVAL}s, deadline ${DEADLINE}s) — IN/OUT pairing per rules #22"
log_beat "started dry_run=${DRY_RUN}"

while true; do
  for svc in "${!COOLDOWN[@]}"; do
    (( COOLDOWN[$svc] > 0 )) && COOLDOWN[$svc]=$(( COOLDOWN[$svc] - 1 ))
  done

  while IFS='|' read -r kind svc agent mid age; do
    [[ "$kind" == "MISS" ]] || continue
    log_beat "MISS ${agent} message_id=${mid} unanswered ${age}s (unit ${svc})"
    log_journal "🔴 answer-monitor: ${agent} message_id=${mid} unanswered for ${age}s (>300s) — NOT normal per rules #22"
    alert="🔴 [answer-monitor @ mini-PC] ${agent}: inbound message_id=${mid} got NO successful reply send for ${age}s (rule: 300s)."

    if [[ "$DRY_RUN" == "1" ]]; then
      log_beat "DRY-RUN: would restart ${svc} + post Discord alert"
      continue
    fi

    if (( COOLDOWN[$svc] > 0 )); then
      log_beat "cooldown active for ${svc} — alert only, no restart"
      post_discord "${alert} Restart skipped (cooldown)." || true
      continue
    fi
    enter_s=$(date -d "$(systemctl --user show "$svc" --property=ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
    if (( $(date +%s) - enter_s < BOOT_GRACE )); then
      log_beat "boot grace for ${svc} — alert only, no restart"
      post_discord "${alert} Restart skipped (service just started)." || true
      continue
    fi
    # preserve session context first (guardian pattern)
    "$HOME/projects/claudeteam/bin/journal-new-backup.sh" "answer-monitor: ${svc} deaf (msg ${mid} unanswered ${age}s)" >/dev/null 2>&1 || true
    if systemctl --user restart "$svc" 2>>"$HEARTBEAT"; then
      log_journal "♻️ answer-monitor: restarted ${svc} (${agent} unresponsive to inbound)"
      post_discord "${alert} Action: restarted ${svc}." || true
    else
      log_journal "❌ answer-monitor: restart of ${svc} FAILED"
      post_discord "${alert} Action: restart FAILED — manual attention needed." || true
    fi
    COOLDOWN[$svc]=$COOLDOWN_SWEEPS
  done < <(sweep 2>>"$HEARTBEAT")

  # positive evidence every 10 sweeps: today's per-agent counters
  (( SWEEP_N++ ))
  if (( SWEEP_N % 10 == 1 )); then
    summary=""
    for entry in "${NODES[@]}"; do
      a="${entry%%|*}"
      s=$(python3 -c "import json;d=json.load(open('$STATS_DIR/$(date +%F)-$a.json'));print(f\"{d['inbound']}in/{d['answered']}ans/{d['misses']}miss\")" 2>/dev/null || echo "0in")
      summary+="$a=$s "
    done
    log_beat "sweep #${SWEEP_N} ok — ${summary}"
  fi

  sleep "$INTERVAL"
done
