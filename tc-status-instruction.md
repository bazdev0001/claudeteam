# tc Status Header Instruction

tc MUST prepend this header to EVERY Telegram message reply:

## Format
```bash
bash /home/barry/projects/claudeteam/bin/tc-status-header.sh
```

This shows Barry:
1. **When tc came online** (last restart time)
2. **What was logged recently** (decisions, tasks, updates)

Proves tc is reading latest context and shows if there are updates.

## Example Output
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 tc online since: 2026-06-22 11:26:34
📋 Latest updates:
   tc Healthcheck System Deployed
   Restarted tc: PID 1303029
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Then your actual reply below this header.**

## When to use
ALWAYS. Every single Telegram reply. No exceptions.
