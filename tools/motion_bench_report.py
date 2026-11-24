#!/usr/bin/env python3
"""Report for tools/motion_bench.sh: one row per course segment, plus a compare to a base run.

Usage: python3 tools/motion_bench_report.py logs/motion_bench/<name>.json [logs/motion_bench/<base>.json]

Per segment (card motion is what the pixel cards draw on top of the gameplay pose):
  speed     mean travel speed, m/s
  weight    mean / max card-motion weight (0 = off, 1 = full swing)
  swing     largest free-hand swing, forward or back, cm
  twist     largest shoulder counter-turn, degrees
  in_step   % of swinging frames where the free arm goes forward with the opposite foot
  steps     foot plants (a foot going from free to locked)
  slide     largest planted-foot slide in one frame, mm (gameplay legs)
  pop       largest frame-to-frame jump of the drawn free hand beyond its smooth path, mm
  react s   how long a reaction drew (react:<name> segments: the player stands and plays it)
  paddle    largest move of the drawn paddle hand away from the gameplay hand, cm
  bob       largest body lift, cm; spin: largest paddle spin, deg
  expr      the standing expression shown most in the segment (expr:<name> segments force one)
  head/look/torso  largest head nod, head turn and torso lean, deg; shrug cm
  knee      mean drawn knee bend of the more bent leg, deg (0 = straight); knee game: the gameplay legs
  raise     largest body lift from standing straight, cm
  stance    the standing leg stance at the end of the segment (stance:<n> segments force one), with
            feet wide / feet fwd (drawn feet apart sideways, and right foot ahead of left, cm),
            hip side (hips toward the right foot, cm), heel (one foot higher than the other, cm),
            knee R / knee L (drawn knee bends, deg), jump (largest one-frame change of the feet, mm)
  grip cm   largest distance of the drawn paddle grip from the drawn paddle hand, beyond the gameplay gap
  feet far  largest sideways gap of the drawn feet along the hip line, cm
  low cm    how far the drawn body is lowered for a side shuffle; feet state: the footwork state shown most
  hop / drop / turn  footwork flow (docs/FOOTWORK_PLAN.md): split-step hop cm, gravity-step body drop cm,
            chest turn toward a diagonal run deg
  feet min  smallest sideways gap of the drawn feet along the hip line, cm (negative = legs crossed)
With a base run: changes per segment, and the gameplay joints (body, hands, shoulders, feet,
paddle) compared frame by frame: IDENTICAL means the change is visual only.
"""
import json, math, sys

def load(path):
    d = json.load(open(path))
    return d, d["frames"]

def segments(frames):
    out, cur = [], None
    for i, f in enumerate(frames):
        if cur is None or f["seg"] != cur["seg"]:
            cur = {"seg": f["seg"], "rows": []}
            out.append(cur)
        cur["rows"].append(f)
    return out

def free_arm(f):
    for side, a in f.get("arms", {}).items():
        if a.get("free"): return side, a
    return None, None

def metrics(rows):
    m = {}
    m["speed"] = sum(r["speed"] for r in rows) / len(rows)
    ws = [r.get("w", 0.0) for r in rows]
    m["w_mean"], m["w_max"] = sum(ws) / len(ws), max(ws)
    swing, twist, ok, n, steps, slide, pop = 0.0, 0.0, 0, 0, 0, 0.0, 0.0
    prev_lock = {}
    pts = []
    for r in rows:
        side, a = free_arm(r)
        if a is not None:
            swing = max(swing, abs(a["off"]))
            pts.append(a["drawn"])
            if abs(a["off"]) > 0.01:
                want = r.get("stride", 0.0) * (1 if side == "right" else -1)
                n += 1
                ok += (a["off"] > 0) == (want > 0)
        twist = max(twist, abs(r.get("twist", 0.0)))
        for s, ft in r["feet"].items():
            if ft["locked"] and prev_lock.get(s) is False: steps += 1
            prev_lock[s] = ft["locked"]
            if ft["locked"]: slide = max(slide, ft["slide"])
    for i in range(1, len(pts) - 1):
        mid = [(pts[i - 1][k] + pts[i + 1][k]) / 2 for k in range(3)]
        pop = max(pop, math.dist(pts[i], mid))
    pad, bob, spin, react_n = 0.0, 0.0, 0.0, 0
    for r in rows:
        for a in r.get("arms", {}).values():
            if not a.get("free"): pad = max(pad, a.get("moved", 0.0))
        bob = max(bob, abs(r.get("bob", 0.0)))
        spin = max(spin, abs(r.get("spin", 0.0)))
        react_n += 1 if r.get("react") else 0
    m.update(react=react_n / 60.0, paddle=pad * 100, bob=bob * 100, spin=spin)
    names = [r.get("expr", "") for r in rows if r.get("expr")]
    m["expr"] = max(set(names), key=names.count) if names else None
    for k in ("head", "look", "torso"): m[k] = max(abs(r.get(k, 0.0)) for r in rows)
    m["shrug"] = max(abs(r.get("shrug", 0.0)) for r in rows) * 100
    m["knee"] = sum(r.get("knee", 0.0) for r in rows) / len(rows)
    m["knee_game"] = sum(r.get("knee_game", 0.0) for r in rows) / len(rows)
    m["raise"] = max(r.get("raise", 0.0) for r in rows) * 100
    end = rows[-1]   # the stance as held at the end of the segment
    m["stance"] = end.get("stance") or None
    for k in ("feet_wide", "feet_fwd", "hip_side", "heel"): m[k] = end.get(k, 0.0) * 100
    for k in ("knee_r", "knee_l"): m[k] = end.get(k, 0.0)
    m["grip_gap"] = max(r.get("grip_gap", 0.0) for r in rows) * 100
    m["low"] = max(r.get("low", 0.0) for r in rows) * 100
    m["hop"] = max(r.get("hop", 0.0) for r in rows) * 100
    m["drop"] = max(r.get("drop", 0.0) for r in rows) * 100
    m["turn"] = max((r.get("turn", 0.0) for r in rows), key=abs)
    locos = [r.get("loco", "") for r in rows if r.get("loco")]
    m["loco"] = max(set(locos), key=locos.count) if locos else None
    m["feet_far"] = max(r.get("feet_side", 0.0) for r in rows) * 100
    m["feet_min"] = min(r.get("feet_side", 1.0) for r in rows) * 100
    m["foot_jump"] = max([abs(b.get(k, 0.0) - a.get(k, 0.0)) for a, b in zip(rows, rows[1:]) for k in ("feet_wide", "feet_fwd")] or [0.0]) * 1000
    m.update(swing=swing * 100, twist=twist, in_step=(100.0 * ok / n) if n else None, steps=steps,
             slide=slide * 1000, pop=pop * 1000)
    return m

COLS = [("speed", "speed m/s", "{:.2f}"), ("w_mean", "w mean", "{:.2f}"), ("w_max", "w max", "{:.2f}"),
        ("swing", "swing cm", "{:.1f}"), ("twist", "twist deg", "{:.1f}"), ("in_step", "in step %", "{:.0f}"),
        ("steps", "steps", "{:d}"), ("slide", "slide mm", "{:.1f}"), ("pop", "pop mm", "{:.1f}"),
        ("react", "react s", "{:.2f}"), ("paddle", "paddle cm", "{:.1f}"), ("bob", "bob cm", "{:.1f}"), ("spin", "spin deg", "{:.0f}"),
        ("head", "head deg", "{:.0f}"), ("look", "look deg", "{:.0f}"), ("torso", "torso deg", "{:.0f}"), ("shrug", "shrug cm", "{:.1f}"),
        ("knee", "knee deg", "{:.0f}"), ("knee_game", "knee game", "{:.0f}"), ("raise", "raise cm", "{:.1f}"),
        ("feet_wide", "feet wide", "{:.0f}"), ("feet_fwd", "feet fwd", "{:.0f}"), ("hip_side", "hip side", "{:.0f}"),
        ("heel", "heel cm", "{:.1f}"), ("knee_r", "knee R", "{:.0f}"), ("knee_l", "knee L", "{:.0f}"), ("grip_gap", "grip cm", "{:.1f}"), ("feet_min", "feet min", "{:.0f}"), ("feet_far", "feet far", "{:.0f}"), ("low", "low cm", "{:.1f}"), ("hop", "hop cm", "{:.1f}"), ("drop", "drop cm", "{:.1f}"), ("turn", "turn deg", "{:.0f}"), ("loco", "feet state", "{}"), ("foot_jump", "jump mm", "{:.1f}"),
        ("stance", "stance", "{}"), ("expr", "expr", "{}")]

def fmt(c, v):
    return "-" if v is None else c[2].format(v)

def table(segs, base=None):
    head = f"{'segment':<23}" + "".join(f"{c[1]:>11}" for c in COLS)
    print(head)
    for i, s in enumerate(segs):
        m = s["m"]
        line = f"{s['seg']:<23}" + "".join(f"{fmt(c, m[c[0]]):>11}" if c[0] != "expr" else f"  {fmt(c, m[c[0]])}" for c in COLS)
        print(line)
        if base is not None and i < len(base) and base[i]["seg"] == s["seg"]:
            b = base[i]["m"]
            diffs = []
            for c in COLS:
                if m[c[0]] is None or b[c[0]] is None or isinstance(m[c[0]], str): diffs.append(f"{'':>11}"); continue
                d = m[c[0]] - b[c[0]]
                diffs.append(f"{('' if abs(d) < 1e-9 else ('+' if d > 0 else '') + c[2].format(d if c[0] != 'steps' else int(d))):>11}")
            if any(x.strip() for x in diffs): print(f"{'  vs base':<23}" + "".join(diffs))

def gameplay_diff(a, b):
    n = min(len(a), len(b))
    worst, first = 0.0, None
    for i in range(n):
        for pa, pb in zip(a[i]["g"], b[i]["g"]):
            d = math.dist(pa, pb)
            if d > worst: worst = d
            if d > 0.001 and first is None: first = i
    return n, worst, first, len(a) != len(b)

def main():
    d, frames = load(sys.argv[1])
    segs = segments(frames)
    for s in segs: s["m"] = metrics(s["rows"])
    base_segs = None
    if len(sys.argv) > 2:
        bd, bframes = load(sys.argv[2])
        base_segs = segments(bframes)
        for s in base_segs: s["m"] = metrics(s["rows"])
    print(f"{sys.argv[1]}: {len(frames)} frames, {d['wall_ms'] / 1000:.1f} s wall; card motion "
          f"{d['perf'].get('card_motion_us_mean', -1)} us/frame mean, {d['perf'].get('card_motion_us_max', -1)} max")
    table(segs, base_segs)
    if base_segs is not None:
        n, worst, first, lens = gameplay_diff(bframes, frames)
        verdict = "IDENTICAL" if worst <= 0.001 and not lens else "DIVERGED"
        extra = f", first at frame {first} ({frames[first]['seg']})" if first is not None else ""
        print(f"gameplay joints vs base: {verdict} (max {worst * 1000:.2f} mm over {n} frames{extra}"
              f"{', different frame count' if lens else ''})")

main()
