# claudeteam — Development Roadmap

Phased plan. Each phase is independently useful and testable. See [[ARCHITECTURE]] / [[DECISIONS]].

## Phase 1 — Telegram ⇄ Claude on Mini PC (+ free voice)  ← CURRENT
Always-on `claude --channels` Telegram session you can chat with; voice notes transcribed
**locally and free** (faster-whisper, open-source Whisper model — NOT the paid OpenAI API).
Pairing + lockdown. Runs in a terminal first to prove it.
- [x] Telegram channel verified working (`@Bazminipcclaude02bot`); token BOM bug fixed.
- [x] Free local voice engine installed + smoke-tested (`faster-whisper 1.2.1`, `base` model,
      `bin/transcribe.py` + `bin/transcribe.sh`).
- [x] Launcher: `bin/start-channel.sh`.
- [x] Voice wiring: `bin/tg-transcribe` (cross-OS) + instructions in `CLAUDE.md`; tested OK.
- [ ] Pair the bot (`/telegram:access pair <code>`) then lock down (`policy allowlist`). ← user does this on first run

## Phase 2 — Durable memory (Obsidian brain)
`~/projects/obsidian` vault (own git repo). Session reads a briefing on start, logs as it
goes, and **summarizes before any reset** — context resets stay cheap without forgetting.

## Phase 3 — Make it a real system service
No-login boot (systemd + linger + Windows "at startup" trigger), auto-restart watchdog,
scheduled (nightly) context reset. Cleanest = run claude natively in WSL (pure Linux service).

## Phase 4 — Portability + shared brain (GitHub sync)
Git repos for obsidian + claudeteam, cron pull/push, conflict-safe layout; clone to the VPS.

## Phase 5 — Multi-host team + more channels
VPS as instance #1; Mac (personal-vault split, never shared); add Discord/Slack;
host-to-host coordination via shared task board + a team chat.

## Notes
- Whisper cost myth: the open-source Whisper *model* is free/offline; only OpenAI's *Whisper API* is paid. We use the free local path.
- Voice models are all free; `base` now, can upgrade to `small`/`medium` for more accuracy.
