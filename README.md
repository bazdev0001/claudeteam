# Team Vault — Briefing (read me first)

This is the shared, durable memory for Barry's **agent fleet**. It is the source of
truth that survives session resets, reboots, and host restarts. Keep it
**non-personal** (see [[ARCHITECTURE#Data boundary]]).

> Status: **Stage 0** — design captured, nothing deployed yet. Created 2026-06-16 on the **mini PC** (Windows 11).

## Start here
- [[ARCHITECTURE]] — the full system design (fleet, node, shared brain, coordination).
- [[DECISIONS]] — what's decided vs still open.
- [[RESPONSIBILITIES]] — who/what owns what (placeholder).
- `journal/` — daily log of conversations + what happened on each host.
  - Latest: [[journal/2026-06-16]]

## The fleet at a glance
| Host | OS | Role | Data class |
|---|---|---|---|
| VPS (instance #1) | Linux | Always-on factory: software, social, content | Non-personal |
| Mini PC (this) | Win 11 | Non-personal worker, local models | Non-personal |
| Mac Air | macOS | Personal assistant | **Personal** (stays local) |

## Bots already created
- `@Bazpchermes01bot` (id 8113658356) → **Hermes** (local Ollama agent on mini PC)
- `@Bazminipcclaude02bot` (id 8682389341) → **Claude Code** channel session (mini PC)

See [[journal/2026-06-16]] for the Telegram fixes done today.
