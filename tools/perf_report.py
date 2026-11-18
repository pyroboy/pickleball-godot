#!/usr/bin/env python3
"""Summarise logs/perf.jsonl from a play session in ~20 lines.

Usage: python3 tools/perf_report.py [--short] [path/to/perf.jsonl]
  --short: ~6 lines (used by tools/bench.sh) to keep output small.
"""
import json, sys, os
from collections import defaultdict

SHORT = "--short" in sys.argv
args = [a for a in sys.argv[1:] if a != "--short"]
path = args[0] if args else os.path.join(os.path.dirname(__file__), "..", "logs", "perf.jsonl")
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
def gameplay_line():
    ev = [r for r in rows if r["kind"] == "event"]
    ends = [r["data"] for r in ev if r["event"] == "rally_end"]
    if not ends: return None
    span = defaultdict(list); last = None
    for r in ev:
        if r["event"] != "state": continue
        t = r["data"]["tick"] / float(meta.get("physics_hz", 30))   # game time, not wall time
        if last: span[last[0]].append(t - last[1])
        last = (r["data"]["to"], t)
    reasons = defaultdict(int)
    for e in ends: reasons[e["reason"]] += 1
    avg = lambda k: sum(span[k]) / len(span[k]) if span[k] else 0
    return (f"Points {len(ends)} (" + ", ".join(f"{k.lower()} {n}" for k, n in sorted(reasons.items(), key=lambda kv: -kv[1])) +
            f") | rally {avg('PLAYING'):.1f}s, between {avg('POINT_SCORED'):.1f}s, serve wait {avg('WAITING'):.1f}s")

if SHORT:
    g = gameplay_line()
    if g: print(g)
    tot = defaultdict(float)
    for r in secs:
        for k, v in r["scopes"].items(): tot[k] += v[0]
    # Top-level = one node's whole _process/_physics_process; everything else is
    # nested inside one of them, so the two lists must not be added together.
    outer = lambda k: k.endswith(".physics") or k.startswith("proc.") or k == "contact.authority"
    by = lambda keep: sorted((k for k in tot if keep(k) and not k.startswith("render.")), key=tot.get, reverse=True)
    print("Systems ms/frame: " + ", ".join(f"{k} {tot[k]/len(secs):.2f}" for k in by(outer)[:4]) +
          " | inside them: " + ", ".join(f"{k} {tot[k]/len(secs):.2f}" for k in by(lambda k: not outer(k))[:3]))
    cause = defaultdict(int)
    for sp in spikes:   # deepest-named non-container scope that took the most time
        inner = {k: v for k, v in sp["top"].items() if not (k.endswith(".physics") or k.startswith("proc."))} or sp["top"]
        cause[(sp["state"], max(inner, key=lambda k: inner[k][0]) if inner else "?")] += 1
    print(f"Spikes >= {meta.get('spike_ms')}ms: {len(spikes)}" + (f", worst {max(s['ms'] for s in spikes)}ms; mostly " +
          ", ".join(f"{k} in {st} x{n}" for (st, k), n in sorted(cause.items(), key=lambda kv: -kv[1])[:2]) if spikes else ""))
    jit = defaultdict(int); frames = defaultdict(int)
    for r in secs:
        for st, n in r.get("state_frames", {r["state"]: r["fps"]}).items(): frames[st] += n
        for k, n in r.get("jitter", {}).items():
            parts = k.split(":"); st = parts[3] if len(parts) > 3 else r["state"]
            jit[(st, ":".join(parts[:3]))] += n
    worst = sorted(jit.items(), key=lambda kv: -kv[1] / max(frames[kv[0][0]], 1))[:3]
    if worst: print("Jitter /1k frames: " + ", ".join(f"{k} {st} {1000*n/max(frames[st],1):.0f}" for (st, k), n in worst))
    sys.exit(0)
print(f"{meta.get('os')} {meta.get('model')} | {meta.get('renderer')} | {len(secs)}s played")
print(f"FPS   median {pct(fps,.5)}  worst-5% {pct(fps,.05)}  min {min(fps)}")
g = gameplay_line()
if g: print(g)
print(f"Frame p95 {pct([r['p95_ms'] for r in secs],.5):.1f}ms typical, worst frame {max(r['max_ms'] for r in secs):.1f}ms")
print(f"Scene draws {pct([r['draws'] for r in secs],.5)}  nodes {max(r['nodes'] for r in secs)}")
by_state_ms = defaultdict(list)
for r in secs: by_state_ms[r["state"]].append(r["avg_ms"])
print("Avg frame ms by state:", ", ".join(f"{s} {pct(v,.5)}" for s, v in sorted(by_state_ms.items())))

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

# ---- motion jitter (sec rows "jitter": {"obj:kind:zone": count}) ----
jit = defaultdict(int); state_frames = defaultdict(int)
for r in secs:
    for st, n in r.get("state_frames", {r["state"]: r["fps"]}).items(): state_frames[st] += n
    for k, n in r.get("jitter", {}).items():
        parts = k.split(":"); st = parts[3] if len(parts) > 3 else r["state"]
        jit[(st,) + tuple(parts[:3])] += n
bursts = [r for r in rows if r["kind"] == "jitter_burst"]
if jit or bursts:
    print("Motion jitter (per 1000 frames of that state; obj kind zone):")
    for (st, obj, kind, zone), n in sorted(jit.items(), key=lambda kv: -kv[1] / max(state_frames[kv[0][0]], 1))[:12]:
        print(f"  {1000 * n / max(state_frames[st], 1):6.1f}/1k  {n:5d}  {obj:5s} {kind:7s} {zone:7s} {st}")
    print(f"  bursts (3+ in 0.5 s, snapshot in log): {len(bursts)}" +
          "".join(f"\n    t={b['t']}s {b['obj']} {b['last_kind']} {b['zone']} {b['state']}" for b in bursts[:8]))
