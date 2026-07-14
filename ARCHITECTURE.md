# Architecture — Agent Fleet with Shared Brain

Captured 2026-06-16. This is a living design doc; update it as decisions land in [[DECISIONS]].

## Vision
A **fleet of agent nodes** across multiple hosts that **share one brain** (this vault)
and **work as a team**. Reachable by the user over chat (Telegram first; Discord/Slack
later). Deployable as one portable "software" package to N hosts (>3 expected).

## The fleet
| Host | OS | Role | Data class | Already runs |
|---|---|---|---|---|
| **VPS** = instance #1 | Linux | Always-on factory: software factory, social media, content creation (video/pics), long-running projects | **Non-personal** | Hermes (DeepSeek v4) + claudeclaw (Claude Code wrapper) |
| **Mini PC** (this) | Win 11 | Non-personal worker, local compute | **Non-personal** | Hermes (Ollama/llama) |
| **Mac Air** | macOS | Personal assistant | **Personal** | TBD |
| future hosts | * | * | * | — |

## The "software" = one node, three shared services
Identical code on every host, parameterized by a per-host `config` (name, role,
data-class, channels, model). Behavior differs by config → scales to N hosts.

A node provides:
1. **Channel agent** — continuous `claude --channels …` session, reachable via Telegram
   (later Discord/Slack), with watchdog + boot-start + reset-safe memory.
   - **Each host needs its OWN bot identity per platform.** One bot cannot run on two
     hosts at once (Telegram/Discord/Slack allow one active connection per bot →
     `Conflict: terminated by other getUpdates request`). This is why we already use
     per-host bot names.
2. **Shared brain** — this git-synced Obsidian vault (memory, plans, tasks, decisions).
3. **Coordination** — hosts work as a team mainly *through the shared brain* (a task
   board), with chat channels for real-time nudges.

## Data boundary (the load-bearing constraint)
Memory sharing is **partitioned by sensitivity**:
- **Team vault** (this repo, private GitHub) — *non-personal only*: plans, tasks, project
  state, decisions, system notes. Synced to **VPS + Mini PC** + future non-personal hosts.
- **Personal vault** (Mac-only) — never leaves the Mac (or a separate private repo only the
  Mac holds). Mac may *read* the team vault but writes personal notes locally.
- Rationale: a single shared repo would leak Mac's personal data to the VPS, Mini PC, and
  GitHub's servers. Encryption can be layered later if needed.

## Continuous memory across hosts (GitHub sync)
- Private GitHub repo holds the team vault.
- Each host: `git pull --rebase → commit → push` on a **systemd/launchd timer** (every few
  min) **+ on session start/end hooks** (pull before work, push after).
- **Conflict-free layout** (per-host-owned files never collide):
  ```
  journal/<host>/YYYY-MM-DD.md   ← host-owned
  tasks/T-0001.md                ← one file per task (small status edits)
  plans/  decisions/  system/<host>.md
  RESPONSIBILITIES.md
  ```
- Real conflicts are rare and **self-healing**: an agent can resolve a git merge conflict
  (it's just a coding task).

## Reset-safe memory (don't burn tokens, don't forget)
Two memory tiers:
- **Volatile context** (in the running session) — cheap, disposable, reset often.
- **Durable memory** (this vault) — permanent source of truth.
Resetting context is safe *only because* everything important is flushed to the vault.
- `SessionStart` hook: inject a compact briefing ([[README]] + recent journal) so a fresh
  session is instantly caught up. **Keep the briefing small** or token bloat just moves to
  startup; full vault stays searchable on demand.
- `Stop`/`SessionEnd` hook (and pre-reset step): write a session **summary to the journal
  before** context is wiped. Reset = "summarize → flush → restart", never just "kill".

## Service layer (watchdog + boot + reset)
- **Watchdog** = process manager `Restart=always` (more reliable than a separate watcher).
- **Boot-start** = systemd `--user` + linger (Linux/WSL, like Hermes today) / launchd (macOS).
- **Context reset** = a timer firing the summarize→restart cycle (e.g. nightly).
- One technical wrinkle: `claude --channels` is interactive; headless it may EOF-exit →
  wrap in a pseudo-terminal (`script`/`setsid` on *nix). To be confirmed during build.

## WSL hosts — additional Windows-side watchdog required
On Windows/WSL hosts, systemd `Restart=always` only covers process crashes *inside* WSL.
Windows can shut down the entire WSL distro (updates, Power Automate, user actions) — killing
all services instantly with no auto-recovery. This is not visible to systemd.

**Fix: Windows Task Scheduler watchdog** (`windows/wsl-watchdog.ps1`):
- Polls `wsl --list --running` every 10 min + at logon (2-min delay).
- Restarts WSL if distro is down; logs to `C:\claudeteam\watchdog.log`.
- Install: `.\windows\install-wsl-watchdog.ps1` (no admin needed, current-user task).
- Root cause: 16.7h downtime on 2026-07-14 from this exact gap. Now fixed.

## Voice (inbound Telegram/Slack voice → text)
- Voice notes arrive as OGG/Opus files. Pipeline: download file → transcribe → inject text.
- Engine: **local Whisper** in WSL/Linux (faster-whisper / whisper.cpp). No per-message API
  cost; reusable by Hermes too (Hermes already has an `audio_cache/`).
- Caveat: the Telegram plugin docs only mention downloading inbound *photos*; if it doesn't
  forward *voice*, patch the local `server.ts` to save the voice file + path.
- Discord differs: live voice channels (real-time audio gateway) = much bigger lift →
  scope Discord/Slack as **text first**, voice only where it's file-based.

## Channels: adding Discord / Slack
- `--channels` takes a comma list:
  `claude --channels plugin:telegram@…,plugin:discord@…,plugin:slack@…`
- Confirmed available in official marketplace: telegram, discord, slack, imessage.
- The memory/voice/service layer is **channel-agnostic** → adding a platform = credentials +
  one line. Effort: Telegram (done-ish) < Discord (bot token + invite) < Slack (Slack app:
  OAuth scopes + tokens + Socket Mode).

## Hosts talking to each other
- **Durable coordination = task board in the vault** (async, survives resets; source of truth).
  Hermes already has a `kanban.db` we may reuse.
- **Real-time = a shared team chat** (one group all host-bots join, @mention each other) —
  notification layer, not memory.

## Relationship to Hermes / claudeclaw (open — see [[DECISIONS]])
- (A) Integrate: layer the node onto Hermes (reuse channels/cron/kanban) where Hermes runs.
- (B) Standalone: self-contained node, Hermes-optional, portable to any host.
- Leaning: build node **(B)-style (self-contained, Hermes-optional)** but **integrate (A)**
  on hosts that already run Hermes.

## Portability
~80% OS-agnostic (vault, hooks in POSIX sh/Node, plugins, Whisper). ~20% per-OS service
shim (systemd vs launchd) + a path/config file. Ship as a **git repo + `install.sh`** that
detects OS (`uname`) and installs the right service flavor. Duplication = `git clone &&
./install.sh`.

## Staged roadmap
- **Stage 0** — Spec + repo skeleton (this doc), per-host `config`, OS-detecting `install.sh`. ← *here*
- **Stage 1** — Team-vault private GitHub repo + sync timer/hooks; prove conflict-free on Mini PC.
- **Stage 2** — Always-on Telegram Claude session on Mini PC (watchdog + reset-safe), reading/writing vault.
- **Stage 3** — VPS as instance #1: `git clone && ./install.sh` (native systemd); joins shared brain.
- **Stage 4** — Voice (Whisper); then Mac (launchd + personal-vault split); then Discord/Slack + team channel.

## Open questions (carry into next session)
1. Data split confirmed? (team vault non-personal on VPS+MiniPC; Mac-only personal vault)
2. Hermes relationship: (A) integrate-where-present + build (B)-portable? or pure standalone?
3. Prove Stage 1–2 on Mini PC (recommended) or straight on VPS?
4. Vault sync: private GitHub repo + timer (recommended) vs Obsidian Sync?
5. Reset cadence (nightly default) and per-session model (Sonnet default for cost).
6. VPS OS/details; does claudeclaw already cover the "always-on Claude session" need there?
