#!/usr/bin/env python3
"""
sync-discord-channels.py — sync ALL guild channels into both bots' Discord allowlists.

WHY: the /discord:access skill opts channels in one at a time. This enumerates every
messageable channel in the server (via each bot token) and writes them into the bot's
access.json, so new channels are picked up automatically and you never hand-add again.

POSTURE: OPEN — each channel is added with requireMention=false and an empty per-channel
allowFrom (any member who can post can trigger the bot). Existing entries are PRESERVED,
so hand-set restrictions are never clobbered. Zero-toil trade-off: fine for a private
server, reconsider before adding outsiders.

Usage:
  python3 bin/sync-discord-channels.py            # both bots
  python3 bin/sync-discord-channels.py athena     # one bot

Pure stdlib (no jq/curl/pip). Tokens read from each node's existing .env, never printed.
"""
import json, os, sys, urllib.request, urllib.error

API = "https://discord.com/api/v10"
CH_DIR = os.path.expanduser("~/.claude/channels")
NODES = {
    "athena": os.path.join(CH_DIR, "discord-athena"),
    "sage":   os.path.join(CH_DIR, "discord-tc2"),
}
# Messageable channel types: 0 text, 5 announcement, 15 forum.
MESSAGEABLE = {0, 5, 15}


def read_token(env_file):
    with open(env_file) as f:
        for line in f:
            if line.startswith("DISCORD_BOT_TOKEN="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def api_get(path, token):
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bot {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def sync_node(name, d):
    env_file, acc = os.path.join(d, ".env"), os.path.join(d, "access.json")
    if not os.path.exists(env_file):
        print(f"[{name}] no .env — skip"); return
    token = read_token(env_file)
    if not token:
        print(f"[{name}] empty token — skip"); return

    try:
        guilds = [g["id"] for g in api_get("/users/@me/guilds", token)]
    except urllib.error.HTTPError as e:
        print(f"[{name}] guild lookup failed: {e} — skip"); return
    if not guilds:
        print(f"[{name}] bot is in no guilds — skip"); return

    ids = set()
    for g in guilds:
        for c in api_get(f"/guilds/{g}/channels", token):
            if c.get("type") in MESSAGEABLE:
                ids.add(c["id"])
    print(f"[{name}] found {len(ids)} messageable channels")

    if os.path.exists(acc):
        with open(acc) as f:
            cfg = json.load(f)
    else:
        cfg = {"dmPolicy": "allowlist", "allowFrom": [], "groups": {},
               "ackReaction": "👀", "replyToMode": "first",
               "textChunkLimit": 2000, "chunkMode": "newline"}

    groups = cfg.setdefault("groups", {})
    added = 0
    for cid in ids:
        if cid not in groups:                       # preserve existing entries
            groups[cid] = {"requireMention": False, "allowFrom": []}
            added += 1

    with open(acc, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    print(f"[{name}] +{added} new, {len(groups)} channels total in access.json")


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for name, d in NODES.items():
        if only and only != name:
            continue
        sync_node(name, d)
    print("Done. Servers re-read access.json on every inbound message — no restart needed.")


if __name__ == "__main__":
    main()
