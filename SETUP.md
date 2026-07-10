# claudeteam — Working Setup (Mini PC / WSL) & how to reproduce on the VPS

The always-on Telegram Claude session runs as a **systemd user service** in WSL Ubuntu.
This is the recipe that actually worked on 2026-06-16 (after a lot of dead ends — see the
GOTCHAS, they will bite again on the VPS/Mac).

## Components
- **claude**: native-Linux install via `curl -fsSL https://claude.ai/install.sh | bash` → `~/.local/bin/claude`.
  (npm `@anthropic-ai/claude-code` gave a Windows `.exe` — do NOT use that for a Linux service.)
- **bun** (for the Telegram plugin MCP server): native binary. `bun.sh/install` needs `unzip`
  (not available without sudo here), so we downloaded `bun-linux-x64.zip` and extracted with
  Python into `~/.bun/bin/bun`.
- **Telegram plugin**: `telegram@claude-plugins-official`, cache under `~/.claude/plugins/`.
- **Voice**: `faster-whisper` (free, local, offline) in `~/projects/claudeteam/.venv-voice`,
  model `base` (cached at `~/.cache/huggingface`). Scripts: `bin/transcribe.py`,
  `bin/transcribe.sh`, `bin/tg-transcribe` (cross-OS path wrapper).

## ~/.claude config that MUST be in place (else the session silently won't start)
- `~/.claude/.credentials.json` — login (copied from the Windows install; reused fine).
- `~/.claude/settings.json` — has `enabledPlugins.telegram@... = true`, `skipDangerousModePermissionPrompt`.
- `~/.claude/channels/telegram/.env` — `TELEGRAM_BOT_TOKEN` (no BOM!), bot `@Bazminipcclaude02bot` (8682389341).
- `~/.claude/channels/telegram/access.json` — `{"dmPolicy":"allowlist","allowFrom":["6062064959"]}` (skips pairing).
- `~/.claude/plugins/{known_marketplaces,installed_plugins}.json` — paths must be **Linux** (`/home/...`), not `C:\...`.
- `~/.claude.json` flags (the onboarding/trust/permission gates that block a headless session):
  - `hasCompletedOnboarding: true`
  - `projects["/home/barry/projects/claudeteam"].hasTrustDialogAccepted: true` (+ `hasCompletedProjectOnboarding`)
  - `bypassPermissionsModeAccepted: true`

## The service
- Unit: `~/.config/systemd/user/claudeteam-channel.service`
  - `ExecStart=/bin/bash /home/barry/projects/claudeteam/bin/run-channel-service.sh` (invoke via bash so it
    does NOT depend on the +x bit — editing the script over the Windows share strips +x → `203/EXEC`).
  - `Restart=always`, `WantedBy=default.target`.
- `bin/run-channel-service.sh` sets PATH (`~/.local/bin:~/.bun/bin:...`) then:
  `exec script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" /dev/null`
  - `script` provides a **pty** — without it claude drops to `--print` mode and exits.
  - `--dangerously-skip-permissions` → no tool-permission prompts (needs `bypassPermissionsModeAccepted`).
- Enable boot-start (no login needed): `loginctl enable-linger barry` (already on) + `systemctl --user enable --now claudeteam-channel.service`.

## Operate
- Status: `systemctl --user status claudeteam-channel.service`
- Restart: `systemctl --user restart claudeteam-channel.service`
- Logs: `journalctl --user -u claudeteam-channel.service` (noisy: the claude TUI renders into the pty).
- Proof it's polling Telegram: a `getUpdates` call returns HTTP 409 Conflict.

## GOTCHAS (will recur on VPS/Mac)
1. Headless claude needs a pty (`script`), or it exits via `--print`.
2. First-run **onboarding + trust + bypass-perms** gates block a non-interactive session — pre-set the
   `~/.claude.json` flags above.
3. Plugin registration copied from another host has that host's **paths** — rewrite to local paths.
4. Editing scripts over `\\wsl.localhost` can strip the **executable bit** → run via `bash`.
5. Killing a Windows-interop claude does NOT reap its child `bun.exe` → orphan pollers. Native-Linux avoids this.
6. PowerShell writes `.env` with a **BOM** → breaks token parsing. Write UTF-8 no-BOM.
