#!/usr/bin/env python3
"""How points end per 100 shots, then AI shot choices, from bench perf logs
(PerfMonitor events and "ai_plan" notes): what the AI chose, and how many high
balls (smash chances) it saw and what it did with them.

Usage: python3 tools/shot_report.py logs/bench_<name>.perf.jsonl [more logs...]
"""
import json, sys
from collections import Counter

# ---- how points end, per 100 shots (the number to compare between bench runs) ----
# Cause is read from the rally_end reason plus the last hit before it:
#   low kitchen contact: that hit was met <= 0.65 m up within 2.6 m of the net
#   soft / fast ball:    the ball the loser failed on left the paddle below / from 10 m/s
def _cause(reason, hit):
    speed = sum(v * v for v in hit["vel"]) ** 0.5 if hit else 0.0
    if reason == "BALL_IN_NET":
        low = hit is not None and hit["pos"][1] <= 0.65 and abs(hit["pos"][2]) <= 2.6
        return "net: low kitchen contact" if low else "net: other contact"
    if reason in ("DOUBLE_BOUNCE", "BODY_HIT"):
        pace = "fast ball" if speed >= 10.0 else "soft ball"
        return f"{pace} {'hit the body' if reason == 'BODY_HIT' else 'not returned'}"
    return reason.lower().replace("_", " ")
causes, shots, points = Counter(), 0, 0
for path in sys.argv[1:]:
    hit = None
    for r in (json.loads(l) for l in open(path)):
        if r.get("kind") != "event": continue
        if r["event"] == "hit": hit = r["data"]; shots += 1
        elif r["event"] == "rally_end":
            causes[_cause(r["data"]["reason"], hit)] += 1; points += 1; hit = None
if points:
    print(f"{points} points, {shots} shots ({shots / points:.1f} per point), {len(sys.argv) - 1} runs. Point endings per 100 shots:")
    for cause, n in causes.most_common():
        print(f"  {cause:28s} {n:3d}  {100.0 * n / max(shots, 1):5.1f}")
    print(f"  {'all':28s} {points:3d}  {100.0 * points / max(shots, 1):5.1f}")

plans = []
for path in sys.argv[1:]:
    plans += [r["data"] for r in (json.loads(l) for l in open(path)) if r.get("kind") == "note" and r.get("note") == "ai_plan"]
if not plans: sys.exit("no ai_plan notes (needs the current player_ai_brain.gd)")
print(f"{len(plans)} AI shot plans: " + ", ".join(f"{k} {n}" for k, n in Counter(p["kind"] for p in plans).most_common()))
# Smash chance: ball at least 1.0 m above the net, balanced, not the opening return.
high = [p for p in plans if p["h"] - p["net"] >= 1.0 and not p["opening"]]
print(f"High balls (>= 1.0 m over the net): {len(high)} -> " + ", ".join(f"{k} {n}" for k, n in Counter(p["kind"] for p in high).most_common()))
for band, lo, hi in (("near net (<3.4 m)", 0, 3.4), ("mid (3.4-5.5 m)", 3.4, 5.5), ("deep (>5.5 m)", 5.5, 99)):
    b = [p for p in high if lo <= p["depth"] < hi]
    if b: print(f"  {band:18s} {len(b):3d}: " + ", ".join(f"{k} {n}" for k, n in Counter(p["kind"] for p in b).most_common()) +
                f" | balanced {sum(p['balanced'] for p in b)}, reach<=1.05 m {sum(p['reach'] <= 1.05 for p in b)}")

# ---- planned vs actual launch (ai_launch notes vs hit events) ----
import math
from collections import defaultdict
rows_all = []
for path in sys.argv[1:]:
    rows_all.append([json.loads(l) for l in open(path)])
res = defaultdict(list)
for rows in rows_all:
    launch = {}
    for k, r in enumerate(rows):
        if r.get("kind") == "note" and r.get("note") == "ai_launch": launch[r["data"]["actor"]] = r["data"]
        if r.get("kind") == "event" and r.get("event") == "hit":
            L = launch.pop(r["data"]["actor"], None)
            if not L: continue
            pv, av = L["vel"], r["data"]["vel"]
            nxt = next((x for x in rows[k + 1:] if x.get("kind") == "event" and x["event"] in ("hit", "rally_end")), None)
            net = nxt is not None and nxt["event"] == "rally_end" and nxt["data"]["reason"] == "BALL_IN_NET"
            res[L["kind"]].append((av[1] - pv[1], math.dist(pv, av), net))
if res:
    print("Planned vs actual launch (actual minus planned; netted = next event was BALL_IN_NET):")
    for k, v in sorted(res.items(), key=lambda kv: -len(kv[1])):
        nets = [x for x in v if x[2]]
        print(f"  {k:7s} n={len(v):3d} netted {len(nets):2d} | avg error {sum(x[1] for x in v)/len(v):.2f} m/s, upward {sum(x[0] for x in v)/len(v):+.2f}" +
              (f" | netted upward {sum(x[0] for x in nets)/len(nets):+.2f}" if nets else ""))
