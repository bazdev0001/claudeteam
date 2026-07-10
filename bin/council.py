#!/usr/bin/env python3
"""LLM Council — fleet-native, multi-MODEL (not just multi-persona).

Karpathy's council insight: independent models reviewing each other beats any single model.
The fifbuilds/Claude-skill version uses ONE model (Claude) wearing 5 persona hats. This box has
4 genuinely different local model families via Ollama (Llama, Gemma, Qwen, Hermes) — all free,
offline, on-box (data-boundary safe). So this runs a REAL multi-model council:

  Stage 1  Independent responses — each model answers the question blind to the others.
  Stage 2  Anonymized peer review — each model ranks + critiques the pooled answers (labels only,
           model identities hidden), so it can't favour its own.
  Stage 3  Chairman — done by Claude (the calling skill) reading this script's JSON output, because
           Claude is the strongest synthesizer available; this script stops after stage 2.

Usage:
  python3 bin/council.py "your question"            -> prints JSON (stages 1-2) + saves a transcript
  COUNCIL_MODELS="qwen3:8b,hermes3:latest" python3 bin/council.py "q"   -> override the panel
"""
from __future__ import annotations
import sys, os, json, time, random, urllib.request

OLLAMA = "http://localhost:11434/api/generate"
DEFAULT_MODELS = ["llama3.2:3b", "gemma4:12b", "qwen3:8b", "hermes3:latest"]
TIMEOUT = int(os.environ.get("COUNCIL_TIMEOUT", "180"))
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".council-out")


def ask(model: str, prompt: str) -> str:
    body = json.dumps({"model": model, "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.7}}).encode()
    req = urllib.request.Request(OLLAMA, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            out = json.load(r).get("response", "").strip()
        # qwen3 etc. emit <think>...</think> — strip it for the council record
        if "</think>" in out:
            out = out.split("</think>", 1)[1].strip()
        return out or "(empty response)"
    except Exception as e:
        return f"(ERROR from {model}: {e})"


def run(question: str, models: list[str]) -> dict:
    # --- Stage 1: independent responses ---
    s1 = []
    for m in models:
        t = time.time()
        ans = ask(m, f"Answer this concisely and concretely. Lead with your recommendation.\n\n{question}")
        s1.append({"model": m, "answer": ans, "secs": round(time.time() - t, 1)})

    # --- anonymize: shuffle + relabel so reviewers can't tell whose answer is whose ---
    labeled = list(s1)
    random.shuffle(labeled)
    pool_letters = [chr(65 + i) for i in range(len(labeled))]  # A, B, C, ...
    pool = "\n\n".join(f"=== Answer {pool_letters[i]} ===\n{labeled[i]['answer']}"
                       for i in range(len(labeled)))
    anon_map = {pool_letters[i]: labeled[i]["model"] for i in range(len(labeled))}

    # --- Stage 2: anonymized peer review ---
    review_prompt = (
        f"Question:\n{question}\n\nHere are anonymous answers from a panel:\n\n{pool}\n\n"
        "You are a reviewer. Rank these answers from best to worst, give a one-line reason for each, "
        "name the single strongest point and the single biggest flaw across all of them. "
        "Be critical and specific. Do not assume any answer is yours."
    )
    s2 = []
    for m in models:
        t = time.time()
        rev = ask(m, review_prompt)
        s2.append({"model": m, "review": rev, "secs": round(time.time() - t, 1)})

    return {"question": question, "models": models, "anon_map": anon_map,
            "pool_letters": pool_letters, "stage1": s1, "stage2": s2,
            "stage1_anonymized": [{"label": pool_letters[i], "answer": labeled[i]["answer"]}
                                  for i in range(len(labeled))]}


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        print("usage: council.py \"<question>\"", file=sys.stderr); sys.exit(1)
    question = sys.argv[1]
    models = [m.strip() for m in os.environ.get("COUNCIL_MODELS", "").split(",") if m.strip()] \
        or DEFAULT_MODELS
    result = run(question, models)
    os.makedirs(OUTDIR, exist_ok=True)
    stamp = str(abs(hash(question)) % 10_000_000)
    path = os.path.join(OUTDIR, f"council-{stamp}.json")
    with open(path, "w") as f:
        json.dump(result, f, indent=2)
    result["_transcript"] = path
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
