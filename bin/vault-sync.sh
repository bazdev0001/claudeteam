#!/usr/bin/env bash
# Auto-commit & push obsidian vault every few minutes.
# Keeps team in sync without waiting for end-of-day distill.

set -euo pipefail
cd /home/barry/projects/obsidian || exit 1

# Pull before committing to avoid silent push failures on multi-host setup
git pull --rebase --quiet 2>/dev/null || true

# Only commit if there are changes
if ! git diff-index --quiet HEAD --; then
  git add -A
  git commit -m "auto: vault update $(date '+%H:%M')" --no-verify 2>/dev/null || true
  git push 2>/dev/null || true
fi
