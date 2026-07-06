#!/usr/bin/env bash
# Kill ONLY Helen-telegram's leftover bridge processes.
# The old inline ExecStopPost killed EVERY "bun server.ts" on the box — each
# Helen restart silently took down Ada's and Sophia's bridges too, leaving them
# deaf until someone noticed. Scope here: bun procs whose environment carries
# Helen's TELEGRAM_STATE_DIR and that are NOT in the live service cgroup.
CG="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/claude-helen-telegram.service/cgroup.procs"
live=" $(cat "$CG" 2>/dev/null | tr '\n' ' ') "
for pid in $(pgrep -f 'bun.*server\.ts' 2>/dev/null); do
  grep -qz "telegram-helen" "/proc/$pid/environ" 2>/dev/null || continue
  [[ "$live" == *" $pid "* ]] && continue
  kill "$pid" 2>/dev/null || true
done
exit 0
