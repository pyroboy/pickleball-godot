#!/usr/bin/env python3
"""Shake of the drawn players (what the eye sees), from a bench frame log (60 fps).

Needs a bench run with FRAME_LOG=1: logs/bench_<name>.frames.jsonl carries the card joints as
drawn each frame (interpolated + card motion). Per joint, in millimetres:
  off-line  d = x(f) - (x(f-2) + x(f+2)) / 2: how far the joint sits off the straight line
            between where it was one physics tick before and after. Smooth motion, even fast,
            gives ~0; a shake gives a zig-zag.
  tremor    frames where |d| >= 4 mm and d points the opposite way to d one tick earlier
            (a 15 Hz back-and-forth), per player-minute
  pops      frames with |d| >= 30 mm, per player-minute
Each joint is measured against its parent so causes separate: torso against the player's root
(body bounce), head / hands / elbows / knees / feet against the torso (limb shake), and the
root itself (travel jerk).

Usage: tools/tremor_report.py <bench name> [more names...]      one column per run
       tools/tremor_report.py <bench name> --worst [N]          the N shakiest moments
"""
import json, math, sys, collections

JOINTS = [("root", "root (travel)", None), ("torso0", "torso", "root"), ("head0", "head", "torso0"),
          ("hand0", "hand A", "torso0"), ("hand1", "hand B", "torso0"), ("paddle", "paddle", "torso0"),
          ("forearm0", "elbow A", "torso0"), ("forearm1", "elbow B", "torso0"),
          ("shin0", "knee A", "torso0"), ("shin1", "knee B", "torso0"),
          ("shoe0", "foot A", "root"), ("shoe1", "foot B", "root")]
TREMOR_MM, POP_MM = 4.0, 30.0

def load(name):
    """-> per player: list of frames {joint: [x, y, z]}, speed, state"""
    out = [[] for _ in range(4)]
    for line in open(f"logs/bench_{name}.frames.jsonl"):
        r = json.loads(line); dr = r.get("drawn") or {}
        for p in range(4):
            j = dr.get(f"j{p}")
            if j is None: out[p].append(None); continue
            j = dict(j); j["root"] = dr.get(f"p{p}")
            out[p].append((j, dr.get(f"v{p}", 0.0), r.get("state", ""), r.get("t", 0.0)))
    return out

def measure(frames):
    """-> {label: [tremor/min, pops/min, rms mm]}, worst moments"""
    cnt = collections.Counter(); pops = collections.Counter(); sq = collections.Counter(); n = collections.Counter()
    moving = collections.Counter(); worst = []
    for p in range(4):
        fr = frames[p]
        for key, label, parent in JOINTS:
            xs = []
            for f in fr:
                if f is None or f[0].get(key) is None or (parent and f[0].get(parent) is None): xs.append(None); continue
                a = f[0][key]; b = f[0][parent] if parent else (0.0, 0.0, 0.0)
                xs.append((a[0] - b[0], a[1] - b[1], a[2] - b[2]))
            ds = [None] * len(xs)
            for i in range(2, len(xs) - 2):
                a, b, c = xs[i - 2], xs[i], xs[i + 2]
                if a is None or b is None or c is None: continue
                ds[i] = tuple(b[k] - (a[k] + c[k]) / 2 for k in range(3))
            for i in range(4, len(ds)):
                d, e = ds[i], ds[i - 2]
                if d is None: continue
                m = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2) * 1000
                n[label] += 1; sq[label] += m * m
                if m >= POP_MM: pops[label] += 1
                if e is None: continue
                me = math.sqrt(e[0] ** 2 + e[1] ** 2 + e[2] ** 2) * 1000
                if m >= TREMOR_MM and me >= TREMOR_MM and d[0] * e[0] + d[1] * e[1] + d[2] * e[2] < 0:
                    cnt[label] += 1
                    if fr[i][1] > 0.5: moving[label] += 1
                    worst.append((m, p, fr[i][3], label, fr[i][2], fr[i][1]))
    res = {}
    for key, label, parent in JOINTS:
        if n[label]:
            mins = n[label] / 60.0 / 60.0   # player-minutes of frames
            res[label] = [cnt[label] / mins, pops[label] / mins, math.sqrt(sq[label] / n[label]), 100 * moving[label] / max(1, cnt[label])]
    return res, worst

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if "--worst" in sys.argv:
    k = int(args[1]) if len(args) > 1 else 15
    res, worst = measure(load(args[0]))
    seen = set(); shown = 0
    for m, p, t, label, state, v in sorted(worst, reverse=True):
        key = (p, int(t), label)
        if key in seen: continue
        seen.add(key); shown += 1
        print(f"  {m:6.1f} mm  p{p}  t={t:6.2f}s  {label:14s} {state:12s} speed {v:.1f} m/s")
        if shown >= k: break
    sys.exit(0)
results = {name: measure(load(name))[0] for name in args}
print("tremor per player-minute (pops per player-minute) rms mm | % while moving")
print(f"  {'joint':14s}" + "".join(f"{n[:24]:>30s}" for n in args))
for key, label, parent in JOINTS:
    row = f"  {label:14s}"
    for name in args:
        r = results[name].get(label)
        row += f"{r[0]:9.0f} ({r[1]:4.0f}) {r[2]:5.1f} | {r[3]:3.0f}%   " if r else f"{'-':>30s}"
    print(row)
tot = {name: sum(r[0] for r in results[name].values()) for name in args}
print(f"  {'TOTAL tremor':14s}" + "".join(f"{tot[n]:9.0f}{'':21s}" for n in args))
