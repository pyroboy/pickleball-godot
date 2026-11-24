#!/usr/bin/env python3
"""Drive deterioration report (docs/PLAYER_FEEL_PLAN.md). Reads benches run with PRESSURE=<team>
(that team drives every rally ball) and shows how drives and the replies to them change as the
drive streak grows and stamina drains:

  by drive number in a run of drives (1, 2, 3, 4+) and by the driver's stamina (70+, 50-70, <50):
    drive speed, large misses, how the drive ended (in play / net-out / winner)
  the defender's reply, by the defender's stamina:
    counter (11 m/s or more back), reset or dink (soft, low, into the kitchen), pop-up (soft
    but peaking 1.9 m or more, or landing mid-court 2.4-4.6 m), won / lost the point

Usage: python3 tools/drive_report.py --team=0 logs/bench_<name>_s*.perf.jsonl
"""
import json, sys, math, collections

team = next((int(a.split("=")[1]) for a in sys.argv if a.startswith("--team=")), 0)
paths = [a for a in sys.argv[1:] if not a.startswith("--")]
TEAM = lambda actor: 0 if actor in (0, 2) else 1

def band(st):
    return "70+" if st >= 70 else ("50-70" if st >= 50 else "<50")

drives = collections.defaultdict(lambda: collections.Counter())   # key -> counters
speeds = collections.defaultdict(list)
replies = collections.defaultdict(collections.Counter)
stam_low = []
for path in paths:
    rows = [json.loads(l) for l in open(path) if l.strip()]
    plan = {}; run = 0
    contacts = []   # (actor, kind, speed, stamina, large_miss, plan_excess, idx)
    pending = {}
    for r in rows:
        k = r.get("kind"); d = r.get("data", {})
        if k == "note" and r["note"] == "ai_plan": plan[d["actor"]] = d
        elif k == "note" and r["note"] == "ai_launch": pending[d["actor"]] = d["kind"]
        elif k == "note" and r["note"] == "execution" and not d.get("serve"):
            p = plan.get(d["actor"], {})
            contacts.append({"actor": d["actor"], "kind": pending.get(d["actor"], "?"), "st": d.get("stamina", 100),
                             "lm": d.get("large_miss", False), "excess": p.get("h", 0) - p.get("net", 1), "speed": None})
        elif k == "event" and r["event"] == "hit" and contacts and contacts[-1]["speed"] is None:
            contacts[-1]["speed"] = math.hypot(*d["vel"])
            # reply shape from plain gravity: apex height and landing depth past the net
            (x, y, z), (vx, vy, vz) = d["pos"], d["vel"]
            t = (vy + (vy * vy + 2 * 9.81 * max(0.0, y - 0.075)) ** 0.5) / 9.81
            contacts[-1]["apex"] = y + max(0.0, vy) ** 2 / (2 * 9.81)
            contacts[-1]["land"] = abs(z + vz * t)
        elif k == "note" and r["note"] == "point_ending":
            contacts.append({"end": d})
    # walk rallies
    rally = []
    for c in contacts + [{"end": None}]:
        if "end" not in c: rally.append(c); continue
        end = c["end"]; run = 0
        for i, x in enumerate(rally):
            if TEAM(x["actor"]) != team: continue
            if x["kind"] not in ("DRIVE", "SMASH"): run = 0; continue
            run += 1
            nxt = rally[i + 1] if i + 1 < len(rally) else None
            nxt2 = rally[i + 2] if i + 2 < len(rally) else None
            key_n = str(min(run, 4)) + ("+" if run >= 4 else "")
            if TEAM(x["actor"]) == team: stam_low.append(x["st"])
            outcome = "in play" if nxt else ("winner" if end and end.get("winner") == team else ("net/out" if end and end.get("cause") else ("lost" if end else "unfinished")))
            for key in (("drive #", key_n), ("driver stamina", band(x["st"]))):
                drives[key][outcome] += 1; drives[key]["n"] += 1; drives[key]["large miss"] += x["lm"]
                if x["speed"]: speeds[key].append(x["speed"])
            if nxt:
                if nxt2 is None and not (nxt.get("speed") or 0): rep = "lost point" if end and end.get("winner") == team else "won point"
                elif (nxt.get("speed") or 0) >= 11.0 or nxt["kind"] in ("SPEED_UP", "SMASH", "DRIVE"): rep = "counter"
                elif nxt.get("apex", 0) >= 1.9 or 2.4 <= nxt.get("land", 0) <= 4.6: rep = "pop-up"
                elif nxt2 is None: rep = "lost point" if end and end.get("winner") == team else "won point"
                else: rep = "reset/dink"
                replies[band(nxt["st"])][rep] += 1; replies[band(nxt["st"])]["n"] += 1
        rally = []

print(f"Drive deterioration: team {team} drives every ball, {len(paths)} runs")
print(f"  {'':22s} {'n':>4s} {'speed':>6s} {'large miss':>10s} {'in play':>8s} {'net/out':>8s} {'winner':>7s}")
for key in sorted(drives):
    c = drives[key]; n = max(1, c["n"]); sp = speeds[key]
    print(f"  {key[0] + ' ' + key[1]:22s} {c['n']:4d} {sum(sp) / max(1, len(sp)):6.1f} {100 * c['large miss'] / n:9.0f}% {100 * c['in play'] / n:7.0f}% {100 * c['net/out'] / n:7.0f}% {100 * c['winner'] / n:6.0f}%")
print("  Defender's reply by defender stamina:")
for b in ("70+", "50-70", "<50"):
    c = replies.get(b)
    if not c: continue
    n = max(1, c["n"])
    print(f"    {b:6s} n={c['n']:4d}  " + ", ".join(f"{k} {100 * c[k] / n:.0f}%" for k in ("counter", "reset/dink", "pop-up", "won point", "lost point")))
if stam_low:
    s = sorted(stam_low)
    print(f"  Driver stamina at drives: median {s[len(s) // 2]:.0f}, p10 {s[len(s) // 10]:.0f}, min {s[0]:.0f}")
