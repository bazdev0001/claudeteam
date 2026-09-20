#!/usr/bin/env bash
# aiassist-callpath-watch.sh — AI Assistance demo-DID call-path monitor (gap O1,
# production-readiness-2026-09-19.md step 0.4).
#
# WHAT IT PROVES (all read-only, all free — no calls are ever placed):
#   1. Retell platform is up (public statuspage).
#   2. The demo DID +1 (650) 476-2005 still exists on the account AND has an inbound
#      agent bound (this exact failure — number up, nothing answering — is how the line
#      dies silently; the DID showed a bound agent agent_721f6... on 2026-09-19).
#   3. That bound agent still exists / is retrievable (get-agent 200).
#   4. The sales hub page is serving (apex.socialtokens.site/projects/ai-assistance/).
# WHAT IT CANNOT PROVE: actual audio pickup. Only a real call proves that, and every
# real call is billed (CAPABILITIES.md: two AI agents talk to the 15-min cap). A daily
# synthetic call is documented as a PROPOSAL in
# ~/apex/receptionist/docs/callpath-monitor.md — not implemented without Barry's cost OK.
#
# HARD GUARDS:
#   - READ-ONLY: only GET endpoints, ever. No create/update/delete, no create-*-call.
#   - NEVER touches Fuller production (+16504601036 / agent_a29be0ded909acf6c806a0b6d9).
#   - Key comes from ~/apex/.env (gitignored). Never logged, never written to the vault.
#
# Alerting: fleet_alert via sage's bot (bin/fleet-node-lib.sh). Alerts on state change
# (OK->FAIL and FAIL->OK recovery) + re-alert every 6h while still failing, so a dead
# call path cannot rot silently but also cannot spam Barry every 15 minutes.

set -uo pipefail

. /home/barry/projects/claudeteam/bin/fleet-node-lib.sh

NODE="sage"
DID="+16504762005"                       # staging/demo ONLY. Fuller 1036 is off-limits.
DID_ENC="%2B16504762005"
HUB_URL="https://apex.socialtokens.site/projects/ai-assistance/"
STATUS_URL="https://status.retellai.com/api/v2/status.json"
ENV_FILE="/home/barry/apex/.env"
STATE_DIR="$(fleet_stamp_dir aiassist)"
STATE_FILE="$STATE_DIR/callpath.state"        # holds "OK" or "FAIL <epoch-first-seen> <epoch-last-alert>"
REALERT_SECS=$((6*3600))

fails=()

# --- 1. Retell platform status (public, no auth) ---
plat=$(curl -s -m 15 "$STATUS_URL" 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); print(d["status"]["indicator"])
except Exception:
    print("unreachable")' 2>/dev/null || echo unreachable)
case "$plat" in
  none|minor) : ;;   # minor = degraded but likely answering; log only
  *) fails+=("Retell platform status: $plat") ;;
esac
[[ "$plat" == "minor" ]] && fleet_log "[aiassist] retell statuspage indicator=minor (not alerting)"

# --- 2+3. DID bound + agent exists (needs RETELL_API_KEY from apex .env) ---
RETELL_API_KEY=""
if [[ -r "$ENV_FILE" ]]; then
  RETELL_API_KEY=$(grep -m1 '^RETELL_API_KEY=' "$ENV_FILE" | cut -d= -f2-)
fi
if [[ -z "$RETELL_API_KEY" || "$RETELL_API_KEY" == your-* ]]; then
  fails+=("RETELL_API_KEY missing from $ENV_FILE — DID-binding check impossible")
else
  num_json=$(curl -s -m 20 -H "Authorization: Bearer $RETELL_API_KEY" \
    "https://api.retellai.com/get-phone-number/$DID_ENC" 2>/dev/null)
  agent_id=$(printf '%s' "$num_json" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    if d.get("status")=="error": print("ERR:"+d.get("message","api error")); raise SystemExit
    a=(d.get("inbound_agents") or [])
    aid=(a[0].get("agent_id") if a else "") or d.get("inbound_agent_id") or ""
    print(aid if aid else "UNBOUND")
except SystemExit: pass
except Exception: print("ERR:bad response")' 2>/dev/null)
  case "$agent_id" in
    agent_*)
      http=$(curl -s -m 20 -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer $RETELL_API_KEY" \
        "https://api.retellai.com/get-agent/$agent_id" 2>/dev/null) || http=000
      [[ "$http" == "200" ]] || fails+=("demo DID inbound agent $agent_id: get-agent HTTP $http")
      ;;
    UNBOUND) fails+=("demo DID $DID has NO inbound agent bound — line answers nothing") ;;
    ERR:*)   fails+=("get-phone-number $DID failed: ${agent_id#ERR:}") ;;
    *)       fails+=("get-phone-number $DID: unparseable response") ;;
  esac
fi

# --- 4. Hub page ---
# Content check, not just 200: on 2026-09-19 ~22:09 PT the hub was clobbered by a
# 396-byte "Moved" self-redirect stub written through the grok/ai-assistance symlink
# (which points AT the hub file) and still served 200. Real hub is ~74KB and contains
# the demo DID. Guard: minimum size + marker string.
hub_body=$(curl -s -m 20 "$HUB_URL" 2>/dev/null)
hub=$?
if [[ $hub -ne 0 ]]; then
  fails+=("hub page unreachable ($HUB_URL)")
elif (( ${#hub_body} < 10000 )); then
  fails+=("hub page suspiciously small (${#hub_body} bytes — symlink-clobber stub pattern?) ($HUB_URL)")
elif ! grep -q '650' <<<"$hub_body"; then
  fails+=("hub page serving but demo-DID marker missing — wrong content ($HUB_URL)")
fi

# --- state + alerting ---
now=$(date +%s)
prev="OK"; first=0; last_alert=0
if [[ -f "$STATE_FILE" ]]; then
  read -r prev first last_alert < "$STATE_FILE" 2>/dev/null || true
  first=${first:-0}; last_alert=${last_alert:-0}
fi

if ((${#fails[@]} == 0)); then
  if [[ "$prev" == "FAIL" ]]; then
    dur_min=$(( (now - first) / 60 ))
    fleet_alert "$NODE" "✅ aiassist-callpath RECOVERED after ${dur_min}m — demo DID +1(650)476-2005 path checks all green (platform, DID bound, agent, hub)."
  fi
  echo "OK $now 0" > "$STATE_FILE"
  fleet_log "[aiassist] callpath OK (platform=$plat hub=${#hub_body}B)"
else
  msg="🔴 aiassist-callpath: demo DID +1(650)476-2005 path FAILING — $(IFS='; '; echo "${fails[*]}"). Callers may be getting dead air. (read-only checks; no test call placed)"
  if [[ "$prev" != "FAIL" ]]; then
    fleet_alert "$NODE" "$msg"
    echo "FAIL $now $now" > "$STATE_FILE"
  elif (( now - last_alert >= REALERT_SECS )); then
    dur_min=$(( (now - first) / 60 ))
    fleet_alert "$NODE" "$msg Still failing after ${dur_min}m."
    echo "FAIL $first $now" > "$STATE_FILE"
  else
    echo "FAIL $first $last_alert" > "$STATE_FILE"
  fi
  fleet_log "[aiassist] callpath FAIL: ${fails[*]}"
fi
