#!/usr/bin/env python3
"""
claude-usage.py — report REAL Claude subscription usage and warn at a threshold.

HOW IT WORKS
------------
It shells out to the Claude Code CLI in headless mode:  `claude -p "/usage"`.
That command makes a live request, reads the account's `anthropic-ratelimit-*`
headers, and prints the true subscription numbers — the same ones the in-app
/usage panel shows. We parse those percentages. This is the authoritative meter
(session + weekly windows), not a local token estimate.

Costs one tiny request per run, so don't poll it every minute — every 15-30 min
or on session end is plenty.

USAGE
  python3 claude-usage.py                  # human summary
  python3 claude-usage.py --json           # machine-readable
  CLAUDE_USAGE_WARN=70 python3 claude-usage.py

EXIT CODES
  0 = all tracked windows below warn threshold
  1 = at/above warn threshold on any window (use in cron to fire an alert)
  2 = could not read /usage (CLI error / not logged in)
"""
import json, os, re, sys, subprocess

WARN = float(os.environ.get("CLAUDE_USAGE_WARN", "70"))
TIMEOUT = int(os.environ.get("CLAUDE_USAGE_TIMEOUT", "60"))

PATTERNS = {
    "session":      re.compile(r"Current session:\s*(\d+)%"),
    "week_all":     re.compile(r"Current week \(all models\):\s*(\d+)%"),
    "week_sonnet":  re.compile(r"Current week \(Sonnet only\):\s*(\d+)%"),
}
RESET = re.compile(r"resets ([^\n·]+?)\s*\(([^)]+)\)")


def fetch():
    try:
        out = subprocess.run(
            ["claude", "-p", "/usage"],
            capture_output=True, text=True, timeout=TIMEOUT,
        ).stdout
    except FileNotFoundError:
        return None, "claude CLI not found on PATH"
    except subprocess.TimeoutExpired:
        return None, f"/usage timed out after {TIMEOUT}s"
    if "% used" not in out and "session" not in out.lower():
        return None, "unexpected /usage output (not logged in?)"
    return out, None


def parse(text):
    res = {}
    for key, pat in PATTERNS.items():
        m = pat.search(text)
        if m:
            res[key] = int(m.group(1))
    resets = [f"{m.group(1).strip()} ({m.group(2)})" for m in RESET.finditer(text)]
    return res, resets


def main():
    text, err = fetch()
    if err:
        print(f"ERROR: {err}", file=sys.stderr)
        return 2
    pcts, resets = parse(text)
    if not pcts:
        print("ERROR: could not parse any percentages from /usage", file=sys.stderr)
        print(text, file=sys.stderr)
        return 2

    worst = max(pcts.values())
    over = worst >= WARN
    payload = {"pct": pcts, "warn": WARN, "worst": worst, "over": over, "resets": resets}

    if "--json" in sys.argv:
        print(json.dumps(payload, indent=2))
        return 1 if over else 0

    label = {"session": "Session (5h)", "week_all": "Week (all models)", "week_sonnet": "Week (Sonnet)"}
    print("Claude subscription usage (live, authoritative):")
    for k in ("session", "week_all", "week_sonnet"):
        if k in pcts:
            p = pcts[k]
            bar = "#" * (p // 5) + "." * (20 - p // 5)
            flag = "  ⚠" if p >= WARN else ""
            print(f"  {label[k]:<18} {p:>3}%  [{bar}]{flag}")
    if resets:
        print(f"  resets: {', '.join(dict.fromkeys(resets))}")
    if over:
        print(f"\n⚠ WARNING: {worst}% — at/over the {WARN:.0f}% threshold.")
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main())
