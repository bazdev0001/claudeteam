#!/usr/bin/env python3
"""
flush-session.py — WRITE side of the shared brain.

Reads a Claude Code hook payload (JSON on stdin: transcript_path, session_id,
hook_event_name, ...), extracts the conversation turns NOT yet flushed, and appends a
compact record to the current node's raw discussions log in the Obsidian vault.

Deterministic: no model calls. Runs from Stop / PreCompact / SessionEnd hooks so a session's
work lands in the shared vault continuously instead of being trapped in its context.

Fleet-wide: the node name comes from $FLEET_NODE (fallback: hostname → 'minipc' default), so
each host writes to its own  <vault>/<node>/discussions/<date>.md . The script is shared (synced
repo); each host just registers the hooks pointing at it.
"""
import os
import sys
import json
import datetime
import socket

VAULT = os.environ.get("OBSIDIAN_VAULT", "/home/barry/projects/obsidian")
MAXLEN = 600  # truncate long messages in the raw log


def node_name():
    n = os.environ.get("FLEET_NODE")
    if n:
        return n
    host = socket.gethostname().lower()
    # crude mapping; extend per fleet host
    if "vps" in host:
        return "vps"
    if "mac" in host:
        return "mac"
    return "minipc"


def load_payload():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def extract_text(content):
    """Content may be a string or a list of blocks; pull human-readable text only."""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict):
                if b.get("type") == "text" and b.get("text"):
                    parts.append(b["text"])
                elif b.get("type") == "tool_use":
                    parts.append(f"[tool:{b.get('name','?')}]")
                elif b.get("type") == "tool_result":
                    parts.append("[tool_result]")
            elif isinstance(b, str):
                parts.append(b)
        return " ".join(p for p in parts).strip()
    return ""


def iter_messages(transcript_path):
    """Yield (role, text) for user/assistant messages in transcript order."""
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        msg = obj.get("message") if isinstance(obj.get("message"), dict) else obj
        role = msg.get("role") or obj.get("type")
        if role not in ("user", "assistant"):
            continue
        text = extract_text(msg.get("content"))
        if text:
            yield role, text


def state_path(session_id):
    cache = os.path.expanduser("~/.cache")
    os.makedirs(cache, exist_ok=True)
    sid = (session_id or "unknown").replace("/", "_")
    return os.path.join(cache, f"flush-session-{sid}.count")


def read_count(p):
    try:
        with open(p) as f:
            return int(f.read().strip() or "0")
    except Exception:
        return 0


def write_count(p, n):
    try:
        with open(p, "w") as f:
            f.write(str(n))
    except Exception:
        pass


def trunc(s):
    s = " ".join(s.split())  # collapse whitespace/newlines for a compact one-liner
    return s if len(s) <= MAXLEN else s[:MAXLEN] + " …[truncated]"


def main():
    p = load_payload()
    transcript = p.get("transcript_path")
    session_id = p.get("session_id", "unknown")
    event = p.get("hook_event_name", "?")
    if not transcript or not os.path.exists(transcript):
        return 0

    msgs = list(iter_messages(transcript))
    sp = state_path(session_id)
    already = read_count(sp)
    new = msgs[already:]
    if not new:
        return 0

    node = node_name()
    today = datetime.date.today().isoformat()
    now = datetime.datetime.now().strftime("%H:%M")
    outdir = os.path.join(VAULT, node, "discussions")
    os.makedirs(outdir, exist_ok=True)
    outfile = os.path.join(outdir, f"{today}.md")

    new_file = not os.path.exists(outfile)
    with open(outfile, "a", encoding="utf-8") as f:
        if new_file:
            f.write(f"# {today} — {node} discussions (auto-flushed)\n")
            f.write("Raw per-turn capture by flush-session (Stop/PreCompact/SessionEnd hook). "
                    "Distilled nightly. Mark **Decision:**/**Agreement:** for the distiller.\n\n---\n")
        f.write(f"\n### {now} · {event} · session {session_id[:8]}\n")
        for role, text in new:
            who = "Barry" if role == "user" else "Doss"
            f.write(f"- **{who}:** {trunc(text)}\n")

    write_count(sp, len(msgs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
