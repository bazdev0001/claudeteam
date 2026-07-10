# System Description — Barry's Always-On AI Agent System (Mini-PC)

This document explains an always-on AI agent system running on Barry's mini-PC. It is written for someone with no prior knowledge of this setup. Read it top to bottom before doing anything.

---

## What This System Is

Barry has two AI assistants — called **Sage** and **Athena** — running 24/7 on a Windows 11 mini-PC. They are built on Claude (Anthropic's AI), wrapped in a framework called Claude Code. They run inside WSL2 (a Linux environment inside Windows) as background system services that restart automatically if they crash.

Both agents are reachable by Barry through messaging apps: **Telegram** (like WhatsApp) and **Discord** (a chat platform). Barry sends a message from his phone; the agent reads it, thinks, and replies — with a voice audio clip attached so he can listen while driving.

The mini-PC sits on a desk and runs continuously. Barry does not need to be at the machine. He messages from anywhere.

---

## The Two Agents

### Sage — Software Lead and Strategic Partner

Sage is Barry's software engineer and thinking partner. When Barry has a software question, wants code written, needs architecture reviewed, or wants a second opinion on an idea — Sage is who he asks.

Sage's personality: direct, a little dry, short replies. Leads with opinions. Will tell Barry when his idea is wrong and suggest the better path. Not a yes-machine.

**Where Sage lives:**
- Telegram: bot called @Bazminipcclaude02bot
- Discord: bot called Hex, in a private server called "The Bazment"
  - Responds in channel #software (Sage's exclusive channel)
  - Responds in channel #management (shared with Ada, an agent on a separate server)

**What Sage works on:**
- Four software projects owned by Barry:
  - **makemerich** — an iOS mobile app (React Native / Expo). Currently in build pipeline setup stage.
  - **scandocs** — a document scanning/processing project.
  - **selfloveyoga-website** — a website for a yoga brand.
  - **barryauyeung** — Barry's personal/portfolio website.
- Fleet architecture — how all the agents are structured and work together.
- Strategic advice — Sage critiques plans and proposes alternatives.

---

### Athena — Trading and Quant Strategy

Athena is Barry's trading assistant. She manages paper trading systems (practice trading with virtual money before going live) and analyses trading strategies.

**Where Athena lives:**
- Telegram: separate bot from Sage (different token, different inbox)
- Discord: bot called discord-athena
  - Responds only in channel #trading (Athena's exclusive channel)

**What Athena works on:**
- **Options Wheel system** — a paper trading book with $20,000 virtual capital. Sells options contracts on quality stocks (Nvidia, Apple, Microsoft, Google, Amazon) and ETFs (SPY, QQQ).
- **Index Spreads system** — a second $20,000 paper trading book. Defined-risk options spreads on SPY and QQQ. Runs automatically on a schedule at 1:15pm PT daily.
- **Pre-trade review** — before any trade executes, it must be reviewed by 5 independent analytical lenses (signal quality, position size safety, upcoming events, profit potential, portfolio risk). All 5 must agree. If any lens says the risk exceeds 2% of the book, the trade is blocked.
- Tracks all results with clear timeframes (today's profit vs profit since the system started — never reports a number without saying which window it covers).

**Hard rule:** Sage and Athena never respond in each other's channels. If #trading is down, Athena stays silent — she does not go to #software to talk. Same the other way around.

---

## How the Agents Actually Run (Technical)

### Always-On Services

Both agents run as **systemd user services** — background processes managed by Linux's built-in service manager. If a service crashes, it automatically restarts within 5 seconds. This is enabled even when Barry is not logged into the machine (via a Linux feature called "linger").

There are four channel services running continuously:

| Service | Agent | Platform |
|---------|-------|----------|
| claudeteam-channel-tc2.service | Sage | Telegram |
| claudeteam-channel-discord.service | Sage | Discord |
| claudeteam-channel.service | Athena | Telegram |
| claudeteam-channel-discord-athena.service | Athena | Discord |

### How Each Agent Session Starts

When a service starts (or restarts after a crash), it runs through a script chain:

1. The service calls a startup shell script.
2. That script uses a tool called `script` to create a fake terminal — this is required because the Claude software only works interactively (it exits immediately if it detects no terminal).
3. Inside that fake terminal, the script launches Claude with these flags:
   - `--channels plugin:telegram` (or discord) — connects to the messaging platform
   - `--model sonnet` — uses Claude's Sonnet model
   - `--append-system-prompt` — injects the agent's personality and identity from a local file (called a "soul file"). This is a plain text file describing who the agent is, their voice, their values. Sage's soul file lives at `~/.claude/claudeteam-tc2-soul.md`.

4. Claude Code then automatically loads configuration from `~/.claude/settings.json` and the project's `CLAUDE.md` files — these contain behavioural rules, permissions, and startup hooks.

5. On startup, three additional scripts fire automatically (called hooks):
   - **Fleet context injection**: Loads and injects a set of reference files into Claude's working memory so it knows what's happening right now, what decisions have been made, what mistakes to avoid, and what tasks are open. (Described in detail in the Memory section.)
   - **Legacy briefing**: An older script that also injects the same core reference files (both inject similar content — an overlap that exists from the system evolving over time).
   - **I/O monitor**: Kills any runaway disk scan processes (background maintenance, async).

### Bot Isolation

Sage and Athena each have their own bot credentials and their own isolated storage directories on disk. Telegram and Discord only allow one active connection per bot at a time — so giving each agent its own identity prevents them from fighting over connections.

---

## How Agents Remember Things (Memory System)

The agents' context (what they're "thinking about") is wiped every night at 4am and reloaded. This is intentional — it prevents the AI from accumulating too many tokens and slowing down or making errors from context bloat. But anything important must survive the wipe.

### The Shared Vault (Obsidian)

All persistent memory lives in a folder called the **Obsidian vault** at `~/projects/obsidian/`. Obsidian is a note-taking tool that uses plain Markdown files. The vault is a private git repository synced to GitHub every 5 minutes — so it's backed up and (eventually) shareable with agents on other machines.

The vault contains:

- **00-Briefing.md** — A short "who, what, where" orientation file. Any new or reset agent reads this first.
- **journal/YYYY-MM-DD.md** — A daily log. Agents append to this as they work: what Barry asked, what decisions were made, what tool calls happened. Nothing important is left only in chat history.
- **DECISIONS.md** — A log of settled vs open decisions. Once something is decided, it goes here so agents don't re-ask Barry about it. Open items that still need Barry's input are also listed.
- **notes/LEARNINGS.md** — A shared knowledge base. When any agent discovers something non-obvious (a quirk, a working method, a fact about the system), they append it here. Future agents — and future resets of the same agent — read this to avoid reinventing the wheel.
- **notes/FRICTION-LOG.md** — A log of mistakes. When an agent does something wrong that Barry had to correct, it goes here with a rule for what to do instead. Every agent reads this at startup. Examples: "declared something done without testing it," "asked Barry something that was already in the vault," "sent a standalone restart ping instead of folding status into the first real reply."
- **notes/AGENTS.md** — A registry of all agents: who's live, what channels they own, what their IDs are, who to delegate what to.
- **tasks/T-XXXX.md** — One file per task. Each task has its status, what needs to be done, and who owns it. One file per task prevents collisions when multiple agents work on the same vault.

### Startup Injection (How Agents Wake Up Informed)

On every session start (including after the nightly 4am reset), a startup script runs before Barry's first message arrives. It reads the vault files listed above and injects their contents into Claude's working context. By the time Barry's first message arrives, the agent already knows:
- Current fleet state and what phase the system is in
- What happened today (from the journal)
- What decisions have been made (so it doesn't re-propose them)
- What mistakes to avoid (from the friction log)
- What tasks are assigned to it (pulled from GitHub issues)
- The behavioural rulebook and domain knowledge

This means there is no warm-up period. The agent is ready from message one.

### Durable Fact Files (MEMORY.md)

Separate from the vault, Claude Code also maintains a personal memory index at `~/.claude/projects/.../memory/MEMORY.md`. This is an index of small one-fact files — things like "Barry reads on his phone, keep replies short" or "voice replies must be attached to every Telegram message." These survive resets and are loaded automatically.

### Nightly Reset Protocol

The reset timer fires at 4am. Before wiping context, a Stop hook runs:
1. Writes a session summary to today's journal.
2. Commits and pushes the vault to GitHub.

Then the service restarts, the startup hooks fire, and the agent wakes up fully informed from the vault. No memory is lost — it just moves from in-context to on-disk.

---

## Voice Features

### Inbound Voice Messages (Speech to Text)

Barry can send voice notes from his phone instead of typing. When a voice note arrives:
1. The agent downloads the audio file from Telegram.
2. Runs it through a local speech-to-text tool called **faster-whisper** (runs entirely on the mini-PC, offline, no API cost, uses the `medium.en` model for English).
3. Treats the transcript as if Barry typed it and responds normally.

This runs inside WSL (Linux). An alternative Windows-bridge version exists but does not work inside WSL — only the native Linux version is used here.

### Outbound Voice Replies (Text to Speech)

Every reply sent to Barry includes a spoken audio clip attached. This lets Barry listen to replies while driving without reading.

The process:
1. Agent generates the reply text.
2. Runs it through a local text-to-speech tool called **Piper TTS** — a British female voice (`en_GB-jenny_dioco-medium`). Offline, free, no API cost.
3. The resulting audio file (`.ogg` format) is attached to the reply alongside the text.

The audio files are saved to `~/projects/claudeteam/.tts-out/` — they cannot be saved inside the channel plugin's own state directories or the plugin rejects them.

---

## Self-Healing (Bridge Guardian)

There is a known bug in the Claude Code channel plugin: the plugin spawns a child process ("bridge") that actually handles sending/receiving messages to Telegram or Discord. Sometimes this bridge process dies while the main Claude process keeps running. When this happens:
- The background service appears healthy (it's still "active" according to the system manager).
- `ps` shows Claude running.
- But the agent is completely deaf and mute — Barry's messages never arrive, and replies can never send.

This cannot be detected by normal status checks. A dedicated watchdog called `tc-bridge-guardian.sh` solves this:

- Runs in a loop every 5 seconds.
- For each of the four channel services, it looks directly at the Linux kernel's process group data (`/sys/fs/cgroup/`) to check if the bridge process (`bun run ... telegram` or `... discord`) is actually alive inside that service's process group.
- If the bridge has been missing for two consecutive checks (about 10 seconds), it restarts that service.
- Waits 30 seconds after restarting before checking again (to let the new bridge start up cleanly).
- The guardian service itself has `Restart=always` — if the guardian crashes, the system manager restarts it automatically.

The only reliable way to check fleet health: run `bash ~/projects/claudeteam/bin/fleet-status.sh`. This checks bridge presence, not just service state. `systemctl status` can lie.

---

## Discord Status Protocol

When a message arrives in Discord, the agent follows a specific sequence so Barry is never left wondering if his message was seen:

1. Immediately react to the message with a "👀" emoji — confirms it was seen.
2. Post a separate message: "🔧 working on X..." — edit this message live as work progresses (edits don't trigger phone notifications, they just show progress).
3. When done, post a **new** reply with "✅" — this triggers a push notification on Barry's phone.

The rule: never leave Barry in silence while working. The intermediate progress post is mandatory.

---

## Search-Before-Asking Rule

Agents have a strict rule: before asking Barry anything, search all available resources first. The search order is: latest vault state, today's journal, settled decisions, existing tasks, shared knowledge base, mistakes log, domain-specific context, and agent-specific memory. Only after exhausting all of these can an agent ask Barry — or ask another agent.

If an agent asks Barry something that was already in the vault, that incident is logged to the mistakes file (FRICTION-LOG.md) as a rule violation. The goal is that Barry should never have to repeat himself.

---

## Additional Running Services and Automation

Besides the four channel services and the guardian, these also run permanently:

- **fleet-alerter.service** — Sends Barry a Telegram DM whenever the guardian heals a dead bridge or fails to heal one.
- **claudeteam-reset.timer** — Fires at 4:00am nightly to reset session context (described above).
- **daily-attack-plan.timer** — Fires at 6:00am Pacific time. Sends Barry a morning briefing to Telegram: priorities for the day.
- **daily-eod-capture.timer** — Fires at 9:00pm Pacific time. Sends an end-of-day summary to Telegram: what was done, what's open.

---

## Sibling Agents (On a Separate VPS Server — Not on This Machine)

| Agent | Host | Role | Status |
|-------|------|------|--------|
| Ada | VPS (Linux server) | Company operations, always-on gateway | Live |
| Sophia | VPS (Linux server) | VPS software engineering | Defined, not yet deployed |

Sage coordinates with Ada via Discord #management channel. Sophia will be the VPS-side software engineering peer to Sage once deployed. All agents share the same Obsidian vault (once VPS sync is fully set up).

---

## Key File Paths for Reference

| Path | What it is |
|------|-----------|
| ~/projects/claudeteam/ | Production codebase — all scripts and config |
| ~/projects/claudeteam/bin/ | All executable scripts |
| ~/projects/claudeteam/bin/tc-bridge-guardian.sh | The self-healing watchdog script |
| ~/projects/claudeteam/bin/fleet-status.sh | The only reliable health check |
| ~/projects/claudeteam/bin/transcribe.sh | Speech-to-text (Whisper) |
| ~/projects/claudeteam/bin/tg-say.sh | Text-to-speech (Piper) |
| ~/projects/claudeteam/.tts-out/ | Where TTS audio files are saved |
| ~/projects/obsidian/ | The shared memory vault |
| ~/.claude/claudeteam-tc2-soul.md | Sage's identity/personality file (local only, not synced) |
| ~/.claude/claudeteam-channel-soul.md | Athena's identity/personality file (local only, not synced) |
| ~/.claude/channels/telegram-tc2/ | Sage's Telegram state: inbox, credentials |
| ~/.claude/channels/discord-tc2/ | Sage's Discord state |
| ~/.claude/channels/telegram/ | Athena's Telegram state |
| ~/.claude/channels/discord-athena/ | Athena's Discord state |
| ~/.claude/settings.json | Global Claude configuration: hooks, plugins, permissions |
| ~/.config/systemd/user/claudeteam-*.service | The systemd service unit files |
| /tmp/tc-watchdog.log | Guardian's running heartbeat log |
