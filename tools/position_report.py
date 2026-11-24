#!/usr/bin/env python3
"""Positional play report (docs/POSITION_PLAN.md). For bench runs, optionally with
POSITION_TEAM=n (only team n uses the position rules):

  - points won per team
  - per aim (position read kind, or "-" for an ordinary target): how often the opponent's
    reply had to be played from a bad spot (a high pop-up for us: our next contact 0.25 m
    or more over the tape near the kitchen), how often the hitter's team won the point
    within the next 2 shots, and how often it lost within 2
  - smashes: share returned, by defending team (bracing)

Usage: python3 tools/position_report.py logs/bench_<name>_s*.perf.jsonl
"""
import json, sys, collections

TEAM = lambda a: 0 if a in (0, 2) else 1
team_pts = collections.Counter()
aim = collections.defaultdict(collections.Counter)
smash = collections.defaultdict(collections.Counter)
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path) if l.strip()]
    rally = []; plan = {}
    for r in rows:
        k = r.get("kind"); d = r.get("data", {})
        if k == "note" and r["note"] == "ai_plan": plan[d["actor"]] = d
        elif k == "note" and r["note"] == "ai_launch":
            p = plan.get(d["actor"], {})
            rally.append({"actor": d["actor"], "kind": d["kind"], "aim": p.get("aim") or "-", "excess": p.get("h", 0) - p.get("net", 1),
                          "kitchen": p.get("depth", 9) <= 3.4, "opening": p.get("opening", False)})
        elif k == "note" and r["note"] == "point_ending":
            w = d["winner"]; team_pts[w] += 1
            for i, s in enumerate(rally):
                if s["opening"]: continue
                t = TEAM(s["actor"]); key = s["aim"]
                aim[key]["n"] += 1
                nxt_us = next((x for x in rally[i + 1:i + 3] if TEAM(x["actor"]) == t), None)
                if nxt_us and nxt_us["kitchen"] and nxt_us["excess"] >= 0.25: aim[key]["we got a pop-up"] += 1
                left = len(rally) - 1 - i
                if left <= 2: aim[key]["won within 2" if w == t else "lost within 2"] += 1
                if s["kind"] == "SMASH":
                    dt = 1 - t
                    smash[dt]["n"] += 1; smash[dt]["returned"] += left >= 1
            rally = []
pts = sum(team_pts.values())
print(f"{pts} points, {len(sys.argv) - 1} runs | team 0 won {team_pts[0]} ({100 * team_pts[0] / max(1, pts):.0f}%), team 1 won {team_pts[1]} ({100 * team_pts[1] / max(1, pts):.0f}%)")
print(f"  {'aim':18s} {'shots':>6s} {'we got a pop-up':>16s} {'won within 2':>13s} {'lost within 2':>14s}")
for key in sorted(aim, key=lambda k: -aim[k]["n"]):
    c = aim[key]; n = max(1, c["n"])
    print(f"  {key:18s} {c['n']:6d} {100 * c['we got a pop-up'] / n:15.1f}% {100 * c['won within 2'] / n:12.1f}% {100 * c['lost within 2'] / n:13.1f}%")
for t in (0, 1):
    c = smash[t]
    if c["n"]: print(f"  smashes at team {t}: {c['n']}, returned {100 * c['returned'] / c['n']:.0f}%")
