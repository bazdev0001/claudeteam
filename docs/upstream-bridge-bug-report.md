# Bug report: channel plugin transport bridge dies mid-session, session stays alive (deaf+mute)

**File via:** `/bug` in Claude Code, or https://github.com/anthropics/claude-code/issues

---

**Title:** Telegram/Discord channel bridge (`bun run … <transport>`) dies mid-session while
`claude` keeps running — node becomes deaf+mute but service looks healthy

**Environment**
- Claude Code channel plugins: `telegram@claude-plugins-official` 0.0.6, `discord@…` 0.0.4
- Always-on sessions launched under systemd user services (`Restart=always`), `script`-provided PTY,
  `--dangerously-skip-permissions --channels plugin:telegram@…`
- Host: Linux (WSL2), bun runtime, 4 concurrent always-on nodes (2 identities × telegram+discord)

**Summary**
A channel session spawns its transport as a child process (`bun run --cwd …/telegram/0.0.6 start`,
likewise discord). After hours of uptime this bridge child exits/crashes, but the parent `claude`
process keeps running. Result: the bot receives nothing and can send nothing, yet:
- `systemctl is-active` → `active`
- `ps` shows `claude` alive
- the service's `Restart=always` never fires (parent didn't exit)

So the failure is invisible to systemd and to naive health checks. Observed multiple times per day
on every node.

**Impact**
Silent, indefinite outage of an "always-on" bot until a human or external watchdog notices. In our
logs a node was deaf+mute for ~7.5 hours (2026-06-24 ~05:54→13:38) before manual restart.

**Repro (reliable)**
1. Start an always-on channel session.
2. Identify the bridge child in the service cgroup:
   `bun run --cwd ~/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6 start`
3. `kill -9` that bridge PID (simulates the crash).
4. Parent `claude` stays running; service stays `active`; bot is now deaf+mute. It never recovers
   on its own.

**Expected**
Either (a) `claude` detects the bridge child exiting and respawns it, or (b) `claude` exits so
systemd `Restart=always` can recover the whole service.

**Actual**
Bridge stays dead; session lingers alive and unresponsive indefinitely.

**Our workaround (external daemon)**
A 5s loop reads each service's `cgroup.procs`, confirms the expected `bun run … <transport>` child
exists, and `systemctl --user restart`s the service if it's missing for 2 consecutive checks.
Recovers in ~10s. This shouldn't be necessary — the runtime should supervise its own bridge.

**Asks**
1. Supervise the transport bridge inside the session: respawn on child exit, or exit the parent.
2. Expose a real readiness/liveness signal (the bridge being connected), not just process-alive.
