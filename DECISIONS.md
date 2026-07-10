# Decisions

## Decided
- **D1** — Architecture is a **fleet of identical agent nodes + one shared brain** (this vault). See [[ARCHITECTURE]].
- **D2** — **VPS = permanent stable instance #1**, always-on factory, non-personal data.
- **D3** — **Per-host bot identity** per platform (a single bot can't run on multiple hosts simultaneously).
- **D4** — Memory is **partitioned by data sensitivity**: non-personal team vault (shared) vs Mac-only personal vault.
- **D5** — **Reset-safe** design: durable vault is source of truth; reset = summarize→flush→restart.
- **D6** — Watchdog = process-manager `Restart=always`; boot-start via systemd(+linger)/launchd.
- **D7** — Do it **in stages**, repo-first, portability baked in from Stage 0.
- **D8** — **Mac Air handles Barry's personal email + communication; that data is NEVER shared** to the team vault / other hosts / GitHub. (Resolves O1.)
- **D9** — **First prototype target = Mini PC**: a continuous Claude Code session reachable via Telegram **with voice-message support**, which Barry will then iterate on. (Voice is IN the first prototype, not deferred.)

## Open (need Barry's call)
- **O2** — Hermes relationship: (A) integrate where present + build (B)-portable, vs pure standalone.
- **O3** — Prove Stage 1–2 on Mini PC (recommended) or go straight to VPS.
- **O4** — Vault sync: private GitHub repo + timer (recommended) vs Obsidian Sync.
- **O5** — Reset cadence (nightly default) + per-session model (Sonnet default for cost).
- **O6** — Does VPS `claudeclaw` already provide the always-on Claude session, i.e. is the node redundant there?

## Done today (2026-06-16) — see [[journal/2026-06-16]]
- Fixed Hermes Telegram (post-reboot getUpdates conflict; self-healed; outbound verified).
- Fixed Claude channel: removed UTF-8 BOM from `~/.claude/channels/telegram/.env`; verified `claude --channels` works.
