#!/usr/bin/env python3
"""Summarise logs/perf.jsonl from a play session in ~20 lines.

Usage: python3 tools/perf_report.py [path/to/perf.jsonl]
"""
import json, sys, os
from collections import defaultdict

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "logs", "perf.jsonl")
rows = [json.loads(l) for l in open(path) if l.strip()]
meta = next((r for r in rows if r["kind"] == "meta"), {})
secs = [r for r in rows if r["kind"] == "sec"]
spikes = [r for r in rows if r["kind"] == "spike"]
if not secs:
    sys.exit("no data yet")

def pct(vals, p):
    vals = sorted(vals)
    return vals[min(len(vals) - 1, int(len(vals) * p))]

fps = [r["fps"] for r in secs]
print(f"{meta.get('os')} {meta.get('model')} | {meta.get('renderer')} | {len(secs)}s played")
print(f"FPS   median {pct(fps,.5)}  worst-5% {pct(fps,.05)}  min {min(fps)}")
print(f"Frame p95 {pct([r['p95_ms'] for r in secs],.5):.1f}ms typical, worst frame {max(r['max_ms'] for r in secs):.1f}ms")
print(f"CPU   process {pct([r['cpu_ms'] for r in secs],.5)}ms  physics {pct([r['phys_ms'] for r in secs],.5)}ms  "
      f"draws {pct([r['draws'] for r in secs],.5)}  nodes {max(r['nodes'] for r in secs)}")

# FPS by game state
by_state = defaultdict(list)
for r in secs: by_state[r["state"]].append(r)
print("By state (median fps / spikes):", ", ".join(
    f"{s} {pct([r['fps'] for r in rs],.5)}/{sum(r['spikes'] for r in rs)}" for s, rs in sorted(by_state.items())))

# Systems: avg ms per frame across the session, worst single frame
tot, worst, calls, n = defaultdict(float), defaultdict(float), defaultdict(float), len(secs)
for r in secs:
    for k, v in r["scopes"].items():
        tot[k] += v[0]; worst[k] = max(worst[k], v[1])
        if len(v) > 2: calls[k] += v[2]
print("Systems            avg ms/frame  worst ms  calls/frame")
for k in sorted(tot, key=tot.get, reverse=True)[:12]:
    print(f"  {k:22s} {tot[k]/n:6.2f}  {worst[k]:8.1f}  {calls[k]/n:6.1f}")

# Spikes: count and who was biggest in each
print(f"Spikes >= {meta.get('spike_ms')}ms: {len(spikes)}")
blame = defaultdict(int)
for s in spikes:
    top = {k: v for k, v in s["top"].items() if k != "player.physics"}  # container scope
    if top: blame[max(top, key=lambda k: top[k][0])] += 1
    else: blame["(untimed: render/GC/engine)"] += 1
for k, c in sorted(blame.items(), key=lambda kv: -kv[1])[:5]:
    print(f"  {c:4d}x  biggest = {k}")
for s in sorted(spikes, key=lambda s: -s["ms"])[:3]:
    print(f"  worst: t={s['t']}s {s['ms']}ms {s['state']} {s['top']}")
