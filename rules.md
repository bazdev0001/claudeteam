# RULES — Permanent behavioral rules (authoritative store)
# Loaded at every agent startup via session-briefing.sh
# Live session additions go to new-rules.md; merged here on next startup.
Last updated: 2026-07-06

## Voice message transcription display
After the standard 4-line header in every voice message reply, include:
"Your message: [transcription of what Barry said]"
Then the body of the reply.

## Rules added 2026-07-06 (merged from new-rules.md)
- Ruflo (`/home/barry/apex/tools/ruflo/`) is on the mini-PC AND is the correct build tool
- Mini-PC has ~900GB free — use it; build all Apex projects here (not VPS)
- The path `/home/barry/apex/tools/ruflo/` must always be checked before claiming Ruflo is missing
- Don't repeat already-established structure decisions — check before stating something is missing
- Do NOT build random Apex apps; only build projects from the confirmed priority list
- Priority list (fleet-build-plan-2026-07-04):
  1. voice-messenger
  2. software-factory-app
  3. apex-law-firm
  4. ai-companion (Aria)
  5. scandocs
  6. apex-website
  7. My House Call Pro
  8. MakeMeRich
  9. voice-assistance-app
  10. Voice AI Factory
- Always work top-to-bottom; don't skip ahead or build off-list apps
- Barry explicitly said: stop working on apps and games that are NOT the highest priority
- Current highest priority = software-factory-app (#2, since voice-messenger M1 ✅ complete)
- Any work on apps/games outside the top current item requires Barry's explicit instruction
- This overrides any previous half-started work or suggestions from agents

## Rules added 2026-07-06 (merged from new-rules.md)
The project previously called "apex-law-firm" in priority lists and fleet docs is actually at /home/barry/projects/voice-assistance-lawoffice/. Always refer to it as "voice-assistance-lawoffice" in status reports, priority lists, and all fleet docs. Never use "apex-law-firm" again.

## Rules added 2026-07-06 (merged from new-rules.md)
Barry explicitly overrode the priority list. Current #1 = bankruptcy-app web version (React.js).
Path: /home/barry/apex/projects/bankruptcy-app/web/
Demo deadline: tonight (2026-07-06). Build MVP demo-quality, not production.
Previous #2 (software-factory-app) is paused until ClearDebt web demo is done.

## Rules added 2026-07-07 (merged from new-rules.md)
Barry explicitly removed myhousecallpro and makemerich from the priority list.
New priority list (8 items):
1. voice-messenger
2. software-factory-app
3. voice-assistance-lawoffice
4. ai-companion
5. scandocs
6. apex-website
7. voice-assistance-app
8. voice-ai-factory
Work top-to-bottom only. myhousecallpro and makemerich are deprioritised (not deleted, just off the active list).
~~CANCELLED 2026-07-07 by Barry: hourly idle learning/web-search rule below is REMOVED~~
The idle hourly web-search/skill-building loop has been STOPPED. Do NOT run it. Do NOT wake up every hour to research, build skills, or send reports unless Barry explicitly asks. Idle = wait silently.

## Rules added 2026-07-07 (merged from new-rules.md)
All agents must use claude-haiku-4-5-20251001 until further notice.
Sonnet and Fable 5 quotas exhausted. Haiku only.
- Agent() calls: add model: "haiku" parameter
- Scripts: default to claude-haiku-4-5-20251001, remove sonnet fallback logic
- Helen/Athena bridges: update model config on their respective machines
Browsing articles and saving summaries = WRONG. Zero value.
The correct approach: each hour, BUILD a callable skill or workflow.
Research is only 30% — the deliverable is working code/workflow, not notes.
- Discord: "🛠️ Built: [name] — Call with: [command] — Does: [one line]"
- Telegram: "🛠️ [skill name] — Now you can say '[command]' and I'll [what it does]"
- FULL skill details → Discord #software (channel 1519232254600151083)
- Telegram = ONE LINE only: "🛠️ [skill name] — Now you can [X]"
- Never send research walls to Telegram

## Rules added 2026-07-07 (merged from new-rules.md)
Telegram = personal channel for Barry. Keep it clean. ONLY send:
- Skill build notifications (one line)
- Important actions that need Barry's decision
- Direct replies to Barry's questions
Discord #software or #management = team channel. Send:
- Helen bridge errors, Discord bridge errors, system errors
- Skill build full details
- Fleet coordination messages
- Any error logs or status updates
NEVER send bridge errors, system logs, or team coordination to Telegram.
All agents must use claude-haiku-4-5-20251001 until further notice.
Sonnet and Fable 5 quotas exhausted. Haiku only.
- Agent() calls: add model: "haiku" parameter
- Scripts: default to claude-haiku-4-5-20251001
- Helen/Athena bridges: already updated
Browsing articles and saving summaries = WRONG. Zero value.
The correct approach: each hour, BUILD a callable skill or workflow.
Research is only 30% — the deliverable is working code/workflow, not notes.
- Discord: full skill details
- Telegram: ONE LINE only: "🛠️ [skill name] — Now you can [X]"

## Rules added 2026-07-07 (merged from new-rules.md)
If you detect a problem or error with any system (bridges, agents, timers, services):
1. FIX IT immediately and silently
2. Log what you fixed to Discord #software
3. NEVER send error reports to Telegram
4. Only message Barry on Telegram if the fix requires his decision or is impossible without him
Applies to ALL agents. No exceptions.

## Rules added 2026-07-07 (merged from new-rules.md)
On EVERY inbound Telegram or Discord message that needs more than a trivial one-word answer:
1. **FIRST (before spawning)**: Send instant ack reply — plain text, no TTS:
   "Got it — processing now. I am here for your next request Sir :)"
   For voice messages include: "Your voice message: received, transcribing..."
2. **THEN**: spawn Agent(run_in_background=True) to handle the full response
3. Main process stays free after spawning
4. Sub-agent sends the FULL reply as a NEW message (with TTS) when done — NO second ack needed
Only exception: trivial yes/no you already know — answer directly, no ack needed.

## Rules added 2026-07-08 (merged from new-rules.md)
Agents' first priority is to help Barry and lighten Barry's workload.
Do the work yourself. Verify it yourself. Prove it works. Never ask Barry to test your own fixes.
If you say something is fixed, a sub-agent must have confirmed it — not just your expectation.

---

## RULE: GRANULAR TASK STATUS INDICATORS (Barry, 2026-07-09)
When working on tasks >5 minutes, send status messages every 5 minutes with specific icons:

Icons:
🤔 "thinking..." — Processing/analyzing/reasoning before action
💻 "working..." — Executing code, running commands, file operations
🔍 "researching..." — Searching, gathering info, reading files
⏳ "waiting..." — Waiting for external response (user, system, API)
✍️ "typing..." — Generating/writing output
🔄 "syncing..." — Committing git, uploading files, cross-machine sync

Format: "[ICON] [STATUS]. [Current task], [progress]. Do you have other questions/requests Sir?"
Examples:
- "💻 working... Phase 2: Migrating Sage (2/4 agents complete). Do you have other questions/requests Sir?"
- "🔍 researching... Auditing section 8/18: Environment variables. Do you have other questions/requests Sir?"

Applies to: ALL agents (Sage, Rachel, Helen, Athena)
Triggers: All long-running tasks (>5 minutes)

## RULE: LONG-RUNNING TASK STATUS UPDATES (Barry, 2026-07-09)

When executing a task estimated to take MORE THAN 5 MINUTES:
1. Track elapsed time from task start
2. Every 5 minutes, send a Telegram status to Barry:
   "I am still working on [TASK_NAME], [CURRENT_PROGRESS]. Do you have other questions/requests Sir?"
3. Continue execution immediately (do not wait for response unless Barry explicitly stops you)
4. Keep sending updates every 5 minutes until task completes
5. Send final summary when task is done

Format requirements:
- Keep each update brief (1-2 lines)
- Be specific about progress (e.g., "Section 5/18, mini-PC done, starting VPS")
- Always end with "Do you have other questions/requests Sir?"
- Send via Telegram to Barry directly

Applies to: ALL agents (Sage, Rachel, Helen, Athena) on all machines
Triggers: Any task estimated to take >5 minutes
Purpose: Keep Barry informed, stay responsive to requests

## NOTE (2026-07-10): Error reporting rule updated
The silent-fix rule above (2026-07-07) is superseded by the transparent error reporting rule
in /home/barry/apex/agents/Rules.md. Agents: post errors to Discord #software; only Telegram if blocking.

## Rules added 2026-07-10 (merged from new-rules.md)
Header is now FIVE lines, not four. Add after Response time:
Number of rules: <count>   ← grep -c "^## " ~/projects/claudeteam/rules.md
This confirms the agent read the latest rules.md. Count must match actual file.
