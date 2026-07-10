# FLEET-OPS — keeping the channel agents alive 24/7

**One-liner:** The agents ARE built to run 24/7 and self-heal. When one "goes offline," it is
almost always the **transport-bridge-death bug**, and the guardian heals it in ~10s. Do NOT
re-diagnose it as a config/personality/vault problem — that mistake has cost hours.

---

## First move when "an agent isn't responding"

```bash
bash ~/projects/claudeteam/bin/fleet-status.sh
```

This is the ONLY trustworthy health view. `systemctl is-active` and `ps` LIE (see below).
- 🟢 healthy  = service active AND transport bridge live (can truly send/receive)
- 🔴 DEAF+MUTE = service "active" but bridge died → wait ~10s, guardian auto-restarts it
- 🔴 SERVICE DOWN = systemd will Restart=always within 5s
- 🔴 GUARDIAN down = nothing self-heals; `systemctl --user restart tc-bridge-guardian`

If a node is still bad after ~30s: `systemctl --user restart <service>`

---

## The root cause (why this keeps happening)

Each channel node = two linked processes:
1. `claude` session — the brain
2. a **transport bridge** child it spawns: `bun run … telegram` / `bun run … discord`
   — the only part that actually polls Telegram/Discord and sends replies.

**The upstream bug:** the bridge child dies mid-session while `claude` keeps running. So:
- the systemd service stays `active` → its `Restart=always` NEVER fires
- `ps` shows `claude` alive
- but the node is **deaf + mute** — your messages never arrive, replies can't send

This is invisible to naive checks, which is why every incident was first misdiagnosed
("it's stuck", "no CLAUDE.md", "didn't read the vault"). It is NONE of those. It is the bridge.

---

## What makes 24/7 actually work (all verified in place)

| Layer | Mechanism | State |
|-------|-----------|-------|
| Run without login | `loginctl enable-linger barry` | ✅ Linger=yes |
| Process crash | each `*.service` has `Restart=always`, RestartSec=5s, enabled | ✅ |
| **Bridge death** | `tc-bridge-guardian.service` — 5s loop, cgroup bridge check, `systemctl restart` | ✅ active, enabled, Restart=always |
| Guardian crash | systemd `Restart=always` resurrects the guardian itself | ✅ |
| Token/context bloat | `claudeteam-reset.timer` nightly fresh context | ✅ |

The guardian covers all 4 nodes: Athena(tc1) + Sage(tc2), each on telegram + discord.
Proven by live test 2026-06-26: killed a bridge → guardian healed it in ~15s untouched.

---

## What is NOT solved (and the only real cure)

The guardian *recovers from* the bug; it does not *prevent* it. The bridge still dies several
times a day, so each event = a ~10s blip. The only way to eliminate the blips is an **upstream
fix** to the Claude Code channel plugin. See `docs/upstream-bridge-bug-report.md` — file it via
`/bug` or GitHub.

---

## Do NOT do these (they caused the back-and-forth)

- ❌ Don't add per-agent `~/.<name>/CLAUDE.md` or `SOUL.md` as a "fix". Souls load from
  `~/.claude/claudeteam-*-soul.md` (via the node's `_channel-exec*.sh`) + project `CLAUDE.md`.
  A dead config file looks like a fix and changes nothing.
- ❌ Don't add idle-age watchdogs. The old `tc-healthcheck` did this and FALSE-KILLED a healthy
  session (2026-06-24 06:09). Removed. Bridge-presence is the only correct signal.
- ❌ Don't `nohup start-channel.sh`. Use `systemctl --user restart <svc>` — systemd carries the
  PATH/env that fixes the old `exec: claude: not found` failure.

---

## Node → service map

| Node | Identity | Telegram service | Discord service |
|------|----------|------------------|-----------------|
| tc1  | Athena (trading) | `claudeteam-channel.service` | `claudeteam-channel-discord-athena.service` |
| tc2  | Sage (software)  | `claudeteam-channel-tc2.service` | `claudeteam-channel-discord.service` |

Souls: `~/.claude/claudeteam-channel-soul.md` (Athena tg) · `~/.claude/claudeteam-tc2-soul.md` (Sage).
Guardian script: `~/projects/claudeteam/bin/tc-bridge-guardian.sh`. Heartbeat: `/tmp/tc-watchdog.log`.

_Last updated: 2026-06-26 by Claude Code (Opus) during the 24/7-hardening pass._
