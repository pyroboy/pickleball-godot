#!/usr/bin/env python3
"""Stamina experiment report (docs/STAMINA_UX_PLAN.md, bench STAMINA_PIN=...). Per player:
stamina at contact, power-shot speed, large misses, nets/outs charged to them, the pop-ups
they gave (their soft reply let the next opponent contact be 0.25 m or more over the tape
near the kitchen) and the points each team won.

Usage: python3 tools/stamina_report.py logs/bench_<name>_s*.perf.jsonl
"""
import json, sys, math, collections

TEAM = lambda a: 0 if a in (0, 2) else 1
st = collections.defaultdict(list); pw = collections.defaultdict(list)
c = collections.defaultdict(collections.Counter)
team_pts = collections.Counter(); pins = {}
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path) if l.strip()]
    plan = {}; last_contact = None; pending = {}
    for r in rows:
        k = r.get("kind"); d = r.get("data", {})
        if k == "note" and r["note"] == "bench_settings": pins = d.get("stamina_pins", {})
        elif k == "note" and r["note"] == "ai_plan":
            plan[d["actor"]] = d
        elif k == "note" and r["note"] == "ai_launch": pending[d["actor"]] = d["kind"]
        elif k == "note" and r["note"] == "execution" and not d.get("serve"):
            a = d["actor"]; st[a].append(d.get("stamina", 100)); c[a]["shots"] += 1
            c[a]["large miss"] += bool(d.get("large_miss"))
            # pop-up given: previous contact was by the other team and this contact is high
            p = plan.get(a, {})
            if last_contact is not None and TEAM(last_contact) != TEAM(a) and p and p.get("depth", 9) <= 3.4 and p.get("h", 0) - p.get("net", 1) >= 0.25:
                c[last_contact]["pop-ups given"] += 1
            last_contact = a
        elif k == "event" and r["event"] == "hit":
            a = d["actor"]
            if pending.get(a) in ("DRIVE", "SMASH", "SPEED_UP"): pw[a].append(math.hypot(*d["vel"]))
        elif k == "note" and r["note"] == "point_ending":
            team_pts[d["winner"]] += 1
            if d.get("cause"): c[d["actor"]]["nets/outs"] += 1
            last_contact = None
pts = sum(team_pts.values())
print(f"{pts} points, {len(sys.argv) - 1} runs, stamina pins {pins or 'none'} | team 0 won {team_pts[0]} ({100 * team_pts[0] / max(1, pts):.0f}%), team 1 won {team_pts[1]}")
print(f"  {'player':8s} {'stamina med':>11s} {'shots':>6s} {'power speed':>11s} {'large miss':>10s} {'nets/outs':>9s} {'pop-ups given':>13s}")
for a in range(4):
    s = sorted(st[a]); n = max(1, c[a]["shots"])
    print(f"  actor {a}  {s[len(s) // 2] if s else 0:11.0f} {c[a]['shots']:6d} {sum(pw[a]) / max(1, len(pw[a])):11.1f} {100 * c[a]['large miss'] / n:9.1f}% {c[a]['nets/outs']:9d} {100 * c[a]['pop-ups given'] / n:12.1f}%")

# ---- Per point: does the fresher team win? (needs point_ending stamina_start, 2026-11-24 on) ----
gap_rows = collections.defaultdict(lambda: [0, 0])   # gap band -> [points, won by fresher team]
timeline = []
for path in sys.argv[1:]:
    for l in open(path):
        if '"point_ending"' not in l: continue
        d = json.loads(l)["data"]
        stt = d.get("stamina_start")
        if not stt or not any(stt): continue
        t0 = (stt[0] + stt[2]) / 2; t1 = (stt[1] + stt[3]) / 2
        gap = abs(t0 - t1); fresher = 0 if t0 > t1 else 1
        band = "0-10" if gap < 10 else ("10-25" if gap < 25 else "25+")
        gap_rows[band][0] += 1; gap_rows[band][1] += d["winner"] == fresher
        timeline.append((path, t0, t1, min(stt)))
if gap_rows:
    print("Per point, team stamina gap at the serve (team average):")
    for band in ("0-10", "10-25", "25+"):
        n, w = gap_rows[band]
        if n: print(f"  gap {band:6s} {n:4d} points, fresher team won {100 * w / n:.0f}%")
    lows = sorted(x[3] for x in timeline)
    print(f"  lowest player stamina at a serve: median {lows[len(lows) // 2]:.0f}, p10 {lows[len(lows) // 10]:.0f}; "
          f"points with someone under 50 at the serve: {100 * sum(x < 50 for x in lows) / len(lows):.0f}%")
else:
    print("Per point: no stamina_start in these logs (run a new bench).")
