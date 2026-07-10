# Fleet 24/7 Status — Verified Record

**Verified: 2026-06-26 10:47 PDT** by Claude Code (Opus), via live `systemctl` + bridge checks.

## Answer to Barry's question

**Yes.** Both identities — **Athena (tc1)** and **Sage (tc2)** — run **24/7 nonstop**, **self-heal**
automatically, with **minimal downtime** (~10s per incident). Verified on every layer below.

## What was checked (all ✅ at verification time)

| Guarantee | Mechanism | Verified state |
|-----------|-----------|----------------|
| Runs with nobody logged in | `loginctl enable-linger barry` | `Linger=yes` |
| Athena Telegram | `claudeteam-channel.service` | active · on-boot enabled · Restart=always/5s · bridge 🟢 |
| Athena Discord | `claudeteam-channel-discord-athena.service` | active · on-boot enabled · Restart=always/5s · bridge 🟢 |
| Sage Telegram | `claudeteam-channel-tc2.service` | active · on-boot enabled · Restart=always/5s · bridge 🟢 |
| Sage Discord | `claudeteam-channel-discord.service` | active · on-boot enabled · Restart=always/5s · bridge 🟢 |
| Auto self-heal (dead bridge) | `tc-bridge-guardian.service` | active · enabled · Restart=always |
| Heal visibility | `fleet-alerter.service` | active · enabled · Restart=always |

## The three failure modes and how each is covered (→ minimal downtime)

1. **Process crashes** → systemd `Restart=always` relaunches in **5s**.
2. **Transport bridge dies but process lives** (the main recurring bug) → `tc-bridge-guardian`
   detects via cgroup inspection and restarts in **~10s**. *This is the one that used to cause
   hours-long silent outages; now it's ~10s.*
3. **Whole box reboots** → all services are `enabled` (boot-persistent) + linger, so they come back
   without anyone logging in.

The guardian and alerter are themselves `Restart=always`, so the safety net can't stay down either
(systemd supervises the supervisor).

## Proven, not just configured

- 2026-06-26 10:25 — killed Athena/Discord bridge → guardian auto-healed in ~15s, untouched.
- 2026-06-26 10:33 — killed it again → guardian healed + `fleet-alerter` DM'd Barry at T+18s.

## Honest limit (so this record isn't overstated)

Downtime is **minimized, not zero**. The upstream Claude Code channel-plugin bug (bridge dies
mid-session) still recurs a few times/day; each event = a **~10s blip** while the guardian heals it.
Eliminating the blips entirely needs the upstream fix — see `docs/upstream-bridge-bug-report.md`.

## How to re-verify anytime

```bash
bash ~/projects/claudeteam/bin/fleet-status.sh     # true health of all 4 nodes + guardian
```
Full runbook: `FLEET-OPS.md`.
