#!/usr/bin/env bash
set -euo pipefail

# Deploy fleet-health items 3-6, 8 to systemd
cd "$(dirname "$0")"

echo "[*] Copying systemd units..."
mkdir -p ~/.config/systemd/user
cp systemd/*.service ~/.config/systemd/user/
cp systemd/*.timer ~/.config/systemd/user/

echo "[*] Reloading systemd..."
systemctl --user daemon-reload

echo "[*] Enabling timers..."
systemctl --user enable \
  fleet-duplicate-poller-isolate.timer \
  fleet-token-refresh-watch.timer \
  fleet-crash-loop-watch.timer \
  fleet-capability-manifest-check.timer \
  fleet-memory-pressure-watch.timer

echo "[*] Starting timers..."
systemctl --user start \
  fleet-duplicate-poller-isolate.timer \
  fleet-token-refresh-watch.timer \
  fleet-crash-loop-watch.timer \
  fleet-capability-manifest-check.timer \
  fleet-memory-pressure-watch.timer

echo ""
echo "=== DEPLOYED TIMERS ==="
systemctl --user list-timers | grep fleet- || echo "No fleet timers found yet (will appear on next run)"

echo ""
echo "=== UNIT STATUS ==="
systemctl --user status fleet-duplicate-poller-isolate.timer --no-pager || true
systemctl --user status fleet-token-refresh-watch.timer --no-pager || true
systemctl --user status fleet-crash-loop-watch.timer --no-pager || true
systemctl --user status fleet-capability-manifest-check.timer --no-pager || true
systemctl --user status fleet-memory-pressure-watch.timer --no-pager || true

echo ""
echo "✓ Fleet health monitors deployed successfully"
