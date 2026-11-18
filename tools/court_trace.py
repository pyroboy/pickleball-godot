#!/usr/bin/env python3
"""Top-down court trace as text, plus sanity checks on where everyone stands.

Usage: python3 tools/court_trace.py logs/bench_<name>.frames.jsonl [hz=10]
  -> <log>.court.csv  (t, state, pN_x, pN_z for each player, ball_x, ball_y, ball_z)
  -> prints a check report.

Court frame: x across (sideline +-3.05 m), z along (baseline +-6.7 m, net z=0,
kitchen line +-2.13 m). Drawn (interpolated) positions from the frame log.
"""
import json, math, sys
from collections import defaultdict, Counter

HALF_W, HALF_L, NVZ = 3.05, 6.7, 2.13
path = sys.argv[1]
hz = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0
rows = [r for r in (json.loads(l) for l in open(path)) if "drawn" in r]
if not rows: sys.exit("no 'drawn' data: re-run with the current perf_monitor.gd")
fixed = sorted(r["ms"] for r in rows)[len(rows) // 2] < 8.0
t, acc = [], 0.0
for r in rows:
    t.append(acc); acc += 1 / 60 if fixed else r["ms"] / 1000
players = sorted({k for r in rows for k in r["drawn"] if k[0] == "p"})

# ---- CSV at hz ----
out = path.rsplit(".", 1)[0] + ".court.csv"
with open(out, "w") as f:
    f.write("t,state," + ",".join(f"{p}_x,{p}_z" for p in players) + ",ball_x,ball_y,ball_z\n")
    nxt = 0.0
    for i, r in enumerate(rows):
        if t[i] + 1e-9 < nxt: continue
        nxt += 1 / hz
        d = r["drawn"]
        cells = [f"{t[i]:.2f}", r["state"]]
        for p in players: cells += [f"{d[p][0]:.2f}", f"{d[p][2]:.2f}"] if p in d else ["", ""]
        b = d.get("ball")
        cells += [f"{b[0]:.2f}", f"{b[1]:.2f}", f"{b[2]:.2f}"] if b else ["", "", ""]
        f.write(",".join(cells) + "\n")

# ---- checks ----
def zone(z):
    a = abs(z)
    return "kitchen" if a < NVZ else "mid" if a < HALF_L - 1.0 else "baseline" if a <= HALF_L + 0.3 else "behind"

side = {}                                   # usual end per player (sign of z)
for p in players:
    zs = [r["drawn"][p][2] for r in rows if p in r["drawn"]]
    side[p] = 1 if sum(zs) > 0 else -1
teams = defaultdict(list)
for p in players: teams[side[p]].append(p)

time_in = defaultdict(float)                # (player, state, zone) -> s
issues = Counter(); worst = {}
def flag(kind, i, detail, mag):
    issues[kind] += 1
    if kind not in worst or mag > worst[kind][0]: worst[kind] = (mag, f"t={t[i]:.1f}s {rows[i]['state']}: {detail}")
for i, r in enumerate(rows):
    dt = (t[i + 1] - t[i]) if i + 1 < len(rows) else 0
    d, st = r["drawn"], r["state"]
    for p in players:
        if p not in d: continue
        x, _, z = d[p]
        time_in[(p, st, zone(z))] += dt
        if abs(x) > HALF_W + 1.5: flag("far outside sideline (>1.5 m)", i, f"{p} x={x:.2f}", abs(x) - HALF_W)
        if abs(z) > HALF_L + 3.0: flag("far behind baseline (>3 m)", i, f"{p} z={z:.2f}", abs(z) - HALF_L)
        if z * side[p] < -0.3: flag("on the other side of the net", i, f"{p} z={z:.2f}", -z * side[p])
    for s, team in teams.items():
        if len(team) == 2 and all(q in d for q in team):
            a, b = d[team[0]], d[team[1]]
            gap = math.hypot(a[0] - b[0], a[2] - b[2])
            if gap < 0.6: flag("partners overlapping (<0.6 m)", i, f"{team[0]}/{team[1]} gap {gap:.2f} m", 0.6 - gap)
    b = d.get("ball")
    if b:
        if b[1] < -0.05: flag("ball below the floor", i, f"y={b[1]:.2f}", -b[1])
        if b[1] > 8.0: flag("ball very high (>8 m)", i, f"y={b[1]:.2f}", b[1])
        if abs(b[0]) > 15 or abs(b[2]) > 20: flag("ball far off court", i, f"x={b[0]:.1f} z={b[2]:.1f}", abs(b[0]) + abs(b[2]))
    if i:
        for p in players:
            if p in d and p in rows[i - 1]["drawn"]:
                jump = math.dist(d[p], rows[i - 1]["drawn"][p])
                if jump > 0.5: flag("player teleport (>0.5 m in a frame)", i, f"{p} moved {jump:.2f} m", jump)

print(f"{path}: {t[-1]:.0f} s. Top-down CSV ({hz:g} Hz): {out}")
print("Teams by end: " + ", ".join(f"{'+z' if s > 0 else '-z'} end: {'/'.join(v)}" for s, v in teams.items()))
print("\nWhere each player spends time (share of each state):")
for p in players:
    for st in ("WAITING", "SERVING", "PLAYING", "POINT_SCORED"):
        tot = sum(v for (pp, s, _), v in time_in.items() if pp == p and s == st)
        if tot < 0.5: continue
        parts = [f"{z} {100 * time_in[(p, st, z)] / tot:3.0f}%" for z in ("kitchen", "mid", "baseline", "behind") if time_in[(p, st, z)] > 0]
        print(f"  {p} {st:13s} {tot:6.1f}s  " + "  ".join(parts))
print("\nChecks:")
if not issues: print("  all clear")
for k, n in issues.most_common(): print(f"  {n:6d} frames  {k:38s} worst: {worst[k][1]}")

# ---- event timeline (frame log "ev" rows) ----
def xz(v): return f"({v[0]:+.2f},{v[2]:+.2f})" if v else "-"
tl_path = path.rsplit(".", 1)[0] + ".timeline.txt"
lines = []
for i, r in enumerate(rows):
    for e in r.get("ev", []):
        k = e.pop("kind"); e.pop("tick", None)
        d = r["drawn"]
        where = " ".join(f"{p}{xz(d.get(p))}" for p in players)
        b = d.get("ball")
        ball = f"ball({b[0]:+.2f},{b[1]:.2f},{b[2]:+.2f})" if b else ""
        extra = " ".join(f"{a}={xz(v) if isinstance(v, list) and len(v) == 3 else v}" for a, v in e.items())
        lines.append(f"{t[i]:7.2f}s {r['state']:12s} {k:13s} {extra:44s} | {where} {ball}")
open(tl_path, "w").write("\n".join(lines) + "\n")
print(f"\nTimeline: {len(lines)} events -> {tl_path}")
