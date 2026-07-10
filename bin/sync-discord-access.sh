#!/usr/bin/env bash
# sync-discord-access — make the bots auto-join EVERY text channel in the server, open to all members.
#
# Solves two chores so Barry never hand-edits access.json again:
#   1. New CHANNELS  -> queries the Discord API for all text channels and adds any missing ones to
#      BOTH bots' access.json `groups`.
#   2. New MEMBERS   -> sets each group's allowFrom = []  (the server treats empty allowFrom as
#      "anyone in this channel may talk" — server.ts line 287) and requireMention = false.
#
# Idempotent: only writes when something actually changed. Safe to run on a timer.
# Run manually:  bash bin/sync-discord-access.sh
# The channel server re-reads access.json live — no restart needed.
#
# SECURITY NOTE: open mode (allowFrom=[]) means ANY member of a channel can invoke the agents
# (= token cost + they can instruct the agent). Fine for a private server; pass OWNER_ONLY=1 to
# instead restrict to Barry's user id.

set -uo pipefail

OWNER_ID="804750929407901707"
TOKEN_ENV="/home/barry/.claude/channels/discord-tc2/.env"   # any bot in the guild can list channels
FILES=(
  "/home/barry/.claude/channels/discord-tc2/access.json"
  "/home/barry/.claude/channels/discord-athena/access.json"
)
ANCHOR_CHANNEL="1519237387262103625"   # a known channel, used to resolve the guild id

OWNER_ONLY="${OWNER_ONLY:-0}"

python3 - "$TOKEN_ENV" "$ANCHOR_CHANNEL" "$OWNER_ID" "$OWNER_ONLY" "${FILES[@]}" <<'PY'
import json, sys, urllib.request, urllib.error

token_env, anchor, owner, owner_only = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
files = sys.argv[5:]

def tok(f):
    for line in open(f):
        if line.startswith('DISCORD_BOT_TOKEN='):
            return line.split('=',1)[1].strip().strip('"').strip("'")
TOKEN = tok(token_env)
if not TOKEN:
    print("ERROR: no token"); sys.exit(1)

def api(path):
    req = urllib.request.Request("https://discord.com/api/v10"+path,
        headers={"Authorization": f"Bot {TOKEN}", "User-Agent": "DiscordBot (https://local,1.0)"})
    return json.load(urllib.request.urlopen(req))

try:
    guild = api(f"/channels/{anchor}")["guild_id"]
    chans = api(f"/guilds/{guild}/channels")
except urllib.error.HTTPError as e:
    print("ERROR: Discord API", e.code); sys.exit(1)

text_ids = [c["id"] for c in chans if c.get("type") in (0, 5, 15)]
allow_from = [owner] if owner_only == "1" else []   # [] => anyone in the channel

changed_total = 0
for f in files:
    try:
        d = json.load(open(f))
    except FileNotFoundError:
        d = {"dmPolicy": "allowlist", "allowFrom": [owner], "groups": {}, "pending": {}}
    g = d.setdefault("groups", {})
    changed = False
    for cid in text_ids:
        want = {"requireMention": False, "allowFrom": allow_from}
        if g.get(cid) != want:
            g[cid] = want
            changed = True
    if changed:
        json.dump(d, open(f, "w"), indent=2)
        changed_total += 1
    print(f"{f.split('/')[-2]}: {len(g)} channels {'(updated)' if changed else '(no change)'}")

print(f"sync done: {len(text_ids)} text channels, allowFrom={'owner-only' if owner_only=='1' else 'all members'}, {changed_total} file(s) changed")
PY
