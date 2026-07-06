---
title: Runbook — Channel Bridge Guardian (auto-restart deaf channel sessions)
type: runbook
owner: Sage (tc2)
created: 2026-06-24
applies_to: every host that runs an always-on Claude Code channel session (Telegram or Discord)
---

# Channel Bridge Guardian — fleet runbook

**Purpose:** make this fix apply to ALL servers/agents, now and future. The CODE lives on each
host (the `claudeteam` project is NOT git-synced yet — see "Propagation" below), so this vault note
is the **source of truth**: any node can rebuild the guardian from here.

## The bug it fixes
Claude Code's channel plugin spawns its transport **bridge** (`bun … telegram|discord`) as a child
of the `claude` process. When that bridge dies mid-session, `claude` keeps running, so the systemd
service stays `active` and its `Restart=always` **never fires** — the node goes deaf+mute but looks
healthy. This silenced Sage/tc2 on 2026-06-24 (~06:00–06:38).

## The fix
A small **guardian daemon** sweeps every 5s and, per channel session, checks the service's own
cgroup for the bridge it must run. If the bridge is missing for 2 consecutive sweeps (~10s, so a
normal restart gap is ignored), it `systemctl --user restart`s that service → fresh bridge in
~5-10s. Covers Telegram AND Discord. Replaces the old 3-min `tc-healthcheck.timer` (now disabled).

Proven 2026-06-24 07:28: killed tc2's telegram bridge → guardian restored it in ~10s, unattended.

## Install on a node (idempotent)
1. Put the script at `~/projects/claudeteam/bin/tc-bridge-guardian.sh` (content below), `chmod +x`.
2. Edit the `NODES=( … )` array so it lists ONLY the channel services that exist on THIS host,
   each as `label|systemd-unit|bridge-regex` (`bun run.*telegram` or `bun run.*discord`).
   Confirm unit names with: `systemctl --user list-units 'claudeteam-channel*'`.
3. Install the unit at `~/.config/systemd/user/tc-bridge-guardian.service` (content below).
4. `systemctl --user daemon-reload`
5. Retire any old slow watchdog to avoid double-restart races:
   `systemctl --user disable --now tc-healthcheck.timer` (if present).
6. `systemctl --user enable --now tc-bridge-guardian.service`
7. Verify: `tail -f /tmp/tc-watchdog.log` (heartbeats), then kill a bridge child and watch it
   come back within ~10s; guardian restart events also log to `journal/<date>.md`.

## tc-bridge-guardian.sh  (script body)
> Full current copy is on tc2 at `~/projects/claudeteam/bin/tc-bridge-guardian.sh`. Key params:
> `INTERVAL=5` (sweep), `MISS_THRESHOLD=2` (act after ~10s), `COOLDOWN_LOOPS=6` (~30s settle
> after a restart). Detection reads `cgroup.procs` + `/proc/*/cmdline` directly (immune to
> `systemctl status` truncation and the huge `--append-system-prompt` cmdlines). `set -uo pipefail`
> (NOT -e: one node's failure must never abort the loop). CG_BASE =
> `/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice` (adjust UID if not 1000).
> Logic per node per sweep: skip if not installed → skip during cooldown → if service inactive or
> bridge missing, increment miss; once miss≥threshold, restart + verify (poll ≤20s) + cooldown.

## tc-bridge-guardian.service  (systemd user unit)
```ini
[Unit]
Description=tc Bridge Guardian — fast (5s) watchdog that restarts a channel session if its transport bridge dies
After=network.target
[Service]
Type=simple
ExecStart=%h/projects/claudeteam/bin/tc-bridge-guardian.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=default.target
```

## Propagation — how this reaches other servers/agents
- **Behavioral rules** (status-report format, etc.) → already in this vault → the `vault-sync.timer`
  auto-commits + pushes to GitHub every ~5 min, so every node pulls them. ✅
- **This guardian CODE** → does NOT auto-propagate: `~/projects/claudeteam` is **not a git repo**
  on tc2 and systemd units are host-local. Until Phase 4 (git-init + push the `claudeteam` repo and
  clone to other hosts), THIS runbook is how a node gets the fix — follow the install steps above.
- **TODO (fleet):** make `claudeteam` a synced git repo so `bin/` + a deploy script propagate
  automatically; track which hosts have the guardian installed in `RESPONSIBILITIES.md`.
