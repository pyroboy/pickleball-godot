#!/usr/bin/env python3
"""How points end per 100 shots, then AI shot choices, from bench perf logs
(PerfMonitor events and "ai_plan" notes): what the AI chose, and how many high
balls (smash chances) it saw and what it did with them.

Usage: python3 tools/shot_report.py [--targets] logs/bench_<name>.perf.jsonl [more logs...]
  --targets: only the Gameplay v2 targets table (with halves for the noise floor)
"""
import json, sys
from collections import Counter

# ---- Gameplay v2 targets table (docs/GAME_MECHANICS_PLAN.md "Targets") ----
#   python3 tools/shot_report.py --targets logs/bench_x_s*.perf.jsonl
# With 4+ logs it also prints the two halves (first / second half of the logs given),
# whose difference is the noise floor: a row has moved only if it moved more than that.
KITCHEN_LINE, MID_LINE = 2.13, 4.0
POS_AIMS = ("short_on_deep", "feet_running", "back_player_feet", "middle", "angle", "tired_player")
SECS = next((int(a.split("=")[1]) for a in sys.argv if a.startswith("--secs=")), 300)
def targets(paths):
    lengths, endings, kc, kc_up, k_speedups, zones, gap, gap_n = [], Counter(), 0, 0, 0, Counter(), 0, 0
    launches, stam, fallbacks, plans_n, risk_aggr, aggr_fb = Counter(), [], 0, 0, 0, 0
    settings = set(); aims = Counter(); brace = [0, 0]
    for path in paths:
        rows = [json.loads(l) for l in open(path) if l.strip()]
        plan, since_end, fb_pending = {}, 0, {}
        for r in rows:
            k, d = r.get("kind"), r.get("data", {})
            if k == "note":
                n = r["note"]
                if n == "bench_settings": settings.add(f"{['Easy','Medium','Hard'][d['difficulty']]} {'/'.join(d['styles'])}")
                elif n == "brace_seen": brace[1 if d.get("reads") else 0] += 1
                elif n == "ai_plan":
                    plan[d["actor"]] = d; plans_n += 1; fb_pending.pop(d["actor"], None)
                    if d.get("risk") == "aggressive": risk_aggr += 1
                elif n == "ai_fallback":
                    fallbacks += 1; fb_pending[d["actor"]] = True
                    if d.get("risk") == "aggressive": aggr_fb += 1
                elif n == "ai_launch":
                    p = plan.get(d["actor"])
                    if p is None or p.get("opening"): continue
                    launches[d["kind"]] += 1; aims[p.get("aim") or "-"] += 1
                    depth = 1.5 if fb_pending.get(d["actor"]) else p["to"][1]
                    zones["kitchen" if depth < KITCHEN_LINE else ("mid" if depth < MID_LINE else "deep")] += 1
                    if p.get("opp") and len(p["opp"]) == 2:
                        gap_n += 1; mid = (p["opp"][0][0] + p["opp"][1][0]) / 2
                        if not fb_pending.get(d["actor"]) and abs(p["to"][0] - mid) <= 1.0: gap += 1
                    if p["depth"] <= 2.6:
                        kc += 1; kc_up += p["h"] > p["net"]; k_speedups += d["kind"] == "SPEED_UP"
                elif n == "execution" and "stamina" in d and not d.get("serve"): stam.append(d["stamina"])
                elif n == "point_ending":
                    endings[d["ending"]] += 1; endings["net/out"] += d.get("cause") in ("net", "out")
                    endings["unforced net/out"] += d.get("cause") in ("net", "out") and d["ending"] == "UNFORCED_ERROR"
                    lengths.append(d["shots"])
            elif k == "event" and r["event"] == "hit": since_end += 1
            elif k == "event" and r["event"] == "rally_end": since_end = 0
        if since_end: lengths.append(since_end + 1); endings["(unfinished)"] += 1
    pts = sum(endings[e] for e in ("WINNER", "FORCED_ERROR", "UNFORCED_ERROR", "UNCOVERED", "BODY_HIT", "RULE_FAULT"))
    L = sorted(lengths); q = lambda f: L[min(len(L) - 1, int(len(L) * f))] if L else 0
    pc = lambda a, b: 100.0 * a / b if b else 0.0
    zn = sum(zones.values()); ln = sum(launches.values()); S = sorted(stam)
    return {"settings": ", ".join(sorted(settings)) or "?", "points": pts, "unfinished": endings["(unfinished)"],
        "rows": [
        ("Rally length, median", f"{q(0.5)}", "Easy 6-10, Med 8-12, Hard 10-16"),
        ("Rally length, p90", f"{q(0.9)}", "under 30 (Hard 40)"),
        ("Rally length, mean", f"{sum(L) / max(1, len(L)):.1f}", ""),
        ("Rallies longer than 60 shots", f"{sum(x > 60 for x in L)} of {len(L)}", "none"),
        ("Uncovered soft ball (guard)", f"{pc(endings['UNCOVERED'], pts):.0f}%", "under 10%"),
        ("Uncovered per 100 rally shots (guard)", f"{100.0 * endings['UNCOVERED'] / max(1, sum(L)):.2f}", "no higher than base"),
        ("Points per 10 min of play", f"{pts / max(1, len(paths)) * 600 / SECS:.1f}" if SECS else "-", ""),
        ("Kitchen contacts above the net", f"{pc(kc_up, kc):.0f}% of {kc}", "8-15%"),
        ("Speed-ups per 100 kitchen shots", f"{pc(k_speedups, kc):.1f}", "5-10"),
        ("Kitchen / mid / deep landings", " / ".join(f"{pc(zones[z], zn):.0f}" for z in ("kitchen", "mid", "deep")) + "%", "about 60 / 15 / 25"),
        ("Shots at the gap (1 m of midpoint)", f"{pc(gap, gap_n):.0f}%", "25-35%"),
        ("Winner or forced error", f"{pc(endings['WINNER'] + endings['FORCED_ERROR'], pts):.0f}%", "at least 33%"),
        ("Net or out", f"{pc(endings['net/out'], pts):.0f}%", "30-45%"),
        ("Unforced share of nets/outs (guard)", f"{pc(endings['unforced net/out'], endings['net/out']):.0f}%", "under 25%"),
        ("Body hits (guard)", f"{pc(endings['BODY_HIT'], pts):.0f}%", "no higher than base"),
        ("Rule faults", f"{pc(endings['RULE_FAULT'], pts):.0f}%", ""),
        ("Aggressive plans falling back (guard)", f"{pc(aggr_fb, risk_aggr):.0f}% of {risk_aggr} (all fallbacks {fallbacks} of {plans_n} plans)", "under 10%"),
        ("Drives in the shot mix", f"{pc(launches['DRIVE'], ln):.1f}%", "5-15%"),
        ("Shots aimed by position read", f"{pc(sum(aims[a] for a in POS_AIMS), sum(aims.values())):.0f}% (" + ", ".join(f"{a} {aims[a]}" for a in POS_AIMS if aims[a]) + ")", "about 20 / 50 / 80% by level"),
        ("Smash set-ups the defenders read", f"{pc(brace[1], brace[0] + brace[1]):.0f}% of {brace[0] + brace[1]}", "Hard most"),
        ("Shot mix", ", ".join(f"{k} {v}" for k, v in launches.most_common()), ""),
        ("Stamina at contact p10 / median / min", f"{S[len(S) // 10]:.0f} / {S[len(S) // 2]:.0f} / {S[0]:.0f}" if S else "-", ""),
    ]}
def print_targets(paths):
    halves = [paths[: len(paths) // 2], paths[len(paths) // 2:]] if len(paths) >= 4 else []
    tabs = [targets(paths)] + [targets(h) for h in halves]
    t = tabs[0]
    print(f"Targets: {t['points']} points (+{t['unfinished']} unfinished rallies), {len(paths)} runs, settings {t['settings']}")
    head = f"  {'measure':38s} {'all':>18s}" + ("".join(f" {h:>18s}" for h in ("half A", "half B")) if halves else "") + "  target"
    print(head)
    for i, (label, val, tgt) in enumerate(t["rows"]):
        if label == "Shot mix": print(f"  {label}: {val}"); continue
        print(f"  {label:38s} {val:>18s}" + "".join(f" {x['rows'][i][1]:>18s}" for x in tabs[1:]) + f"  {tgt}")
def print_human(paths, me=0, partner=2):
    """Human rows from a phone log (logs/perf.jsonl): actor 0 is you, actor 2 your partner."""
    clean_misses = misses = lost = lost_partner_unforced = 0; stam = []
    for path in paths:
        for r in (json.loads(l) for l in open(path) if l.strip()):
            d = r.get("data", {})
            if r.get("note") == "execution" and d.get("actor") == me and not d.get("serve"):
                if "stamina" in d: stam.append(d["stamina"])
                if d.get("large_miss"):
                    misses += 1; clean_misses += d.get("pressure", 0) < 0.25
            if r.get("note") == "point_ending" and d.get("winner") == 1:
                lost += 1; lost_partner_unforced += d.get("ending") == "UNFORCED_ERROR" and d.get("actor") == partner
    print(f"Human rows: your large misses {misses}, from a clean contact {clean_misses} (limit 0) | points lost {lost}, "
          f"to your partner's unforced error {lost_partner_unforced} (limit 1 in 6) | your stamina min {min(stam) if stam else '-'} "
          f"(limit: below 50 at least once, never stuck below 25)")
if "--human" in sys.argv:
    print_human([a for a in sys.argv[1:] if not a.startswith("--")]); sys.exit(0)
if "--targets" in sys.argv:
    print_targets([a for a in sys.argv[1:] if not a.startswith("--")]); sys.exit(0)

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
