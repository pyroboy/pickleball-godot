#!/usr/bin/env python3
"""Extra data report (bench or phone logs from 2026-11-24 on): stamina costs and time below
the penalty line, tired errors, your release timing / hold / flicks, points lost without a
touch, kitchen-line ownership, AI attack decisions vs their rolls, planned vs actual landing,
and match summaries.

Usage: python3 tools/data_report.py logs/bench_<name>_s*.perf.jsonl   (or a phone perf.jsonl)
"""
import json, sys, math, collections

TEAM = lambda a: 0 if a in (0, 2) else 1
cost = collections.defaultdict(lambda: [0.0, 0.0, 0])          # actor -> streak, block, contacts
low = collections.defaultdict(float)
err_tired = collections.Counter()
timing = []; hold = collections.defaultdict(lambda: [0, 0])     # hold band -> [shots, large misses]
flicks = collections.Counter(); no_touch = collections.Counter(); own = collections.Counter()
dec = collections.Counter(); land = collections.defaultdict(list); matches = []
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path) if l.strip()]
    last_low = {}; plan_to = {}; pend_land = None; last_hit = None; last_input = None
    for r in rows:
        k = r.get("kind"); d = r.get("data", {}); n = r.get("note") or r.get("event")
        if n == "execution" and not d.get("serve"):
            a = d["actor"]
            if "cost" in d: cost[a][0] += d["cost"][0]; cost[a][1] += d["cost"][1]; cost[a][2] += 1
            if not d.get("ai"):
                timing.append(abs(d.get("timing_s", 0.0)))
                if last_input is not None:
                    b = "tap" if last_input.get("touch") else ("<0.5 s" if last_input.get("hold_s", 0) < 0.5 else ("<0.9 s" if last_input.get("hold_s", 0) < 0.9 else "0.9 s+"))
                    hold[b][0] += 1; hold[b][1] += bool(d.get("large_miss"))
                    last_input = None
            pl = d.get("players")
            if pl and all(pl):
                at_line = [sum(1 for i in (0, 2) if abs(pl[i][1]) <= 2.9), sum(1 for i in (1, 3) if abs(pl[i][1]) <= 2.9)]
                own["both" if at_line == [2, 2] else ("team 0" if at_line[0] > at_line[1] else ("team 1" if at_line[1] > at_line[0] else "even"))] += 1
        elif n == "human_input":
            last_input = d
            fl = d.get("flick") or []
            if d.get("touch"): flicks["flick" if fl and math.hypot(*fl) >= 0.25 else "no flick"] += 1
        elif n == "ai_plan":
            plan_to[d["actor"]] = d
            if not d.get("opening"):
                for key, pk in (("pop-up attack", "p_popup"), ("counter", "p_counter")):
                    p = d.get(pk, 0)
                    if p > 0:
                        dec[(key, "offered")] += 1; dec[(key, "taken")] += d.get("roll", 1) < p
        elif n == "hit":
            last_hit = d["actor"]
            p = plan_to.pop(d["actor"], None)
            pend_land = (p.get("kind", "shot"), p.get("to")) if p and p.get("to") else None
        elif n == "bounce" and pend_land:
            kind, to = pend_land; pend_land = None
            pos = d["pos"]
            land[kind].append(math.hypot(pos[0] - to[0], abs(pos[2]) - to[1]))
        elif n == "point_ending":
            for i, s in enumerate(d.get("seconds_low", [])): last_low[i] = s
            if d.get("cause") and d.get("stamina_end"):
                a = d["actor"]
                if 0 <= a < 4: err_tired["tired" if d["stamina_end"][a] < 50 else "fresh"] += 1
            if d.get("winner") == 1 and "human_touched" in d and not d["human_touched"]:
                no_touch[d.get("reason", "?")] += 1
        elif n == "match_summary": matches.append(d)
    for a, s in last_low.items(): low[a] += s

print(f"{len(sys.argv) - 1} logs")
print("Stamina cost extras (sum over contacts): " + ", ".join(f"actor {a}: streak {c[0]:.0f}, fast blocks {c[1]:.0f} ({c[2]} contacts)" for a, c in sorted(cost.items())))
print("Seconds below 50: " + ", ".join(f"actor {a} {s:.0f} s" for a, s in sorted(low.items())))
if err_tired: print(f"Nets/outs by the hitter's stamina at the end: fresh {err_tired['fresh']}, tired (under 50) {err_tired['tired']}")
if timing:
    t = sorted(timing); print(f"Your release timing error: median {1000 * t[len(t) // 2]:.0f} ms, p90 {1000 * t[int(len(t) * .9)]:.0f} ms ({len(t)} swings)")
if hold: print("Your holds -> large misses: " + ", ".join(f"{b} {v[1]} of {v[0]}" for b, v in hold.items()))
if flicks: print("Your touch shots: " + ", ".join(f"{k} {v}" for k, v in flicks.items()))
if no_touch: print("Points your team lost without touching the ball after the serve: " + ", ".join(f"{k} {v}" for k, v in no_touch.most_common()))
if own: print("Kitchen line at contacts (players within 2.9 m of the net): " + ", ".join(f"{k} {100 * v / sum(own.values()):.0f}%" for k, v in own.most_common()))
for key in ("pop-up attack", "counter"):
    if dec[(key, "offered")]: print(f"AI {key}: offered {dec[(key, 'offered')]} plans, rolled into {dec[(key, 'taken')]}")
if land:
    print("Planned vs actual landing (m off): " + ", ".join(f"{k} median {sorted(v)[len(v) // 2]:.2f} (n {len(v)})" for k, v in land.items() if len(v) >= 5))
for m in matches: print(f"Match: {m['score'][0]}-{m['score'][1]}, winner team {m['winner']}, difficulty {m['difficulty']}, seconds below 50 {m['seconds_low']}")
