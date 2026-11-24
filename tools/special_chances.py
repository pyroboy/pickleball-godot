#!/usr/bin/env python3
"""How often a flight gives a special-shot chance (GAME_MECHANICS_PLAN change 8: count the
chances before building each special). Reads hit events (position, velocity) from bench perf
logs and follows each ball with plain gravity (no drag or spin, so a rough count):

  Erne:    crosses the net wide (|x| >= 2.3 m) and lands in the kitchen (an Erne volley
           from beside the post is possible)
  ATP:     lands in the kitchen, then its line after the bounce passes outside the post
           (|x| > 3.35 m) still below 0.9 m, within 2 m of the net (around-the-post shot)
  Tweener: a lob (peak >= 3.5 m) that lands 4.5 m or deeper (it beats a player at the net)

Usage: python3 tools/special_chances.py logs/bench_x_s*.perf.jsonl
"""
import json, sys
G, KITCHEN, POST_X, FLOOR = 9.81, 2.13, 3.35, 0.075

def follow(p, v):
    x, y, z = p; vx, vy, vz = v
    # time to cross the net (z = 0) and to land (y = floor)
    t_net = -z / vz if vz else -1
    a, b, c = -0.5 * G, vy, y - FLOOR
    t_land = (-b - (b * b - 4 * a * c) ** 0.5) / (2 * a)
    peak = y + vy * vy / (2 * G) if vy > 0 else y
    land = (x + vx * t_land, z + vz * t_land)
    net_x = x + vx * t_net if t_net > 0 else None
    # after the bounce: keep the horizontal speed (x 0.8), vertical 0.6 of the landing speed
    vy_land = vy - G * t_land
    after = []
    bvy = -vy_land * 0.6
    for k in range(1, 20):
        t = k * 0.05
        hy = FLOOR + bvy * t - 0.5 * G * t * t
        if hy < FLOOR: break
        after.append((land[0] + 0.8 * vx * t, hy, land[1] + 0.8 * vz * t))
    return net_x, land, peak, after

counts = {"erne": 0, "atp": 0, "tweener": 0}
shots = points = 0
for path in sys.argv[1:]:
    for line in open(path):
        r = json.loads(line)
        if r.get("kind") == "note" and r.get("note") == "point_ending": points += 1
        if r.get("kind") != "event" or r.get("event") != "hit": continue
        d = r["data"]; shots += 1
        net_x, land, peak, after = follow(d["pos"], d["vel"])
        if net_x is None: continue
        in_kitchen = 0 < abs(land[1]) < KITCHEN and abs(land[0]) <= 3.05 and land[1] * d["pos"][2] < 0
        if in_kitchen and abs(net_x) >= 2.3: counts["erne"] += 1
        if in_kitchen and any(abs(px) > POST_X and py < 0.9 and abs(pz) < 2.0 for px, py, pz in after): counts["atp"] += 1
        if peak >= 3.5 and abs(land[1]) >= 4.5 and abs(land[0]) <= 3.05: counts["tweener"] += 1
print(f"{shots} rally shots, {points} points, {len(sys.argv) - 1} runs")
for k, n in counts.items():
    print(f"  {k:8s} {n:4d} chances = {100.0 * n / max(1, shots):.2f} per 100 shots"
          + (f", {n / max(1, points) * 21:.1f} per 21-point match" if points else ""))
