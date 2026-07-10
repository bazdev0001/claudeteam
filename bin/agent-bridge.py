#!/usr/bin/env python3
"""agent-bridge.py — supervised, TURN-CAPPED dialogue between Sage and Athena in the
Discord #minipc-team channel.

Why: the Discord plugin ignores messages authored by other bots (anti-loop), so the two
live listeners can't hear each other. This bridge GENERATES each turn with a headless
`claude -p` call using the speaker's soul, then posts it through that agent's own bot token.
A hard turn cap means it can never run away or burn tokens endlessly.

Usage:  bin/agent-bridge.py ["opening line"] [turns]
  env:  BRIDGE_TURNS (default 6)  BRIDGE_MODEL (default claude-sonnet-4-6)  BRIDGE_CHANNEL
"""
import json, os, subprocess, sys, urllib.request
from pathlib import Path

HOME = Path.home()
CHANNEL = os.environ.get("BRIDGE_CHANNEL", "1519237387262103625")   # #minipc-team
MODEL = os.environ.get("BRIDGE_MODEL", "claude-sonnet-4-6")          # banter -> cheap/fast
OPENING = sys.argv[1] if len(sys.argv) > 1 else \
    "Quick fleet sync - what's our single top priority right now, and is anything blocking you?"
TURNS = int(sys.argv[2]) if len(sys.argv) > 2 else int(os.environ.get("BRIDGE_TURNS", "6"))

def env_token(d):
    for line in (HOME / ".claude/channels" / d / ".env").read_text().splitlines():
        if line.startswith("DISCORD_BOT_TOKEN="):
            return line.split("=", 1)[1].strip()
    raise SystemExit(f"no token in {d}")

AGENTS = {
    "Sage":   {"token": env_token("discord-tc2"),
               "soul": (HOME / ".claude/claudeteam-discord-soul.md").read_text()},
    "Athena": {"token": env_token("discord-athena"),
               "soul": (HOME / ".claude/claudeteam-discord-athena-soul.md").read_text()},
}

def post(token, text):
    text = (text.strip() or "(...)")[:1900]
    req = urllib.request.Request(
        f"https://discord.com/api/v10/channels/{CHANNEL}/messages",
        data=json.dumps({"content": text}).encode(), method="POST",
        headers={"Authorization": f"Bot {token}", "Content-Type": "application/json",
                 "User-Agent": "DiscordBot (https://github.com/bazdev0001/claudeteam, 1.0)"})
    urllib.request.urlopen(req, timeout=20)

def generate(speaker, other, transcript):
    soul = AGENTS[speaker]["soul"]
    prompt = (f"You are {speaker}, talking with your sibling {other} in the fleet's "
              f"#minipc-team Discord channel. Reply with ONE short, in-character message "
              f"(max 2-3 sentences) that advances the conversation. Do NOT prefix it with "
              f"your name.\n\nConversation so far:\n{transcript}")
    out = subprocess.run(
        ["claude", "-p", "--model", MODEL, "--dangerously-skip-permissions",
         "--append-system-prompt", soul, prompt],
        capture_output=True, text=True, timeout=150)
    return out.stdout.strip()

print(f"[bridge] channel={CHANNEL} turns={TURNS} model={MODEL}", flush=True)
post(AGENTS["Sage"]["token"], OPENING)
transcript = f"Sage: {OPENING}"
print(f"Sage: {OPENING}", flush=True)

speaker, other = "Athena", "Sage"
for i in range(TURNS):
    reply = generate(speaker, other, transcript) or "(...no response...)"
    post(AGENTS[speaker]["token"], reply)
    transcript += f"\n{speaker}: {reply}"
    print(f"{speaker}: {reply}", flush=True)
    speaker, other = other, speaker
print(f"[bridge] done after {TURNS} turns (hard cap - stops automatically).", flush=True)
