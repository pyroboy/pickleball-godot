#!/usr/bin/env python3
"""Timeline of the poses each player played in a bench run (physics ticks, 30 Hz).

Reads logs/bench_<name>.pose.jsonl.gz (the i0..i3 pose-info entries written by PerfMonitor)
and logs/bench_<name>.perf.jsonl (hits). One line per change: time, stroke pose, the base pose
blended onto it (with its mix), swing phase and flags. Hits are marked.

Usage: tools/pose_timeline.py <bench name> [player 0-3] [--from S] [--to S] [--summary]
  --summary   per player: time spent in each stroke + base pose pair, and which pairs were
              on at contact (the poses you actually see when the ball is hit)
  --flights   AI pose prediction per incoming ball: how often the predicted contact pose and the
              shown pose flipped, how late the last change came before contact, the charge at
              contact, and whether the pose shown at contact is the one predicted 0.3 s earlier
"""
import gzip, json, sys, collections

STROKES = ["Forehand", "Forward", "Backhand", "Medium Overhead", "High Overhead", "Low Forehand",
           "Low Forward", "Low Backhand", "Charge Forehand", "Charge Backhand", "Wide Forehand",
           "Wide Backhand", "Volley Ready", "Mid-Low Forehand", "Mid-Low Backhand", "Mid-Low Forward",
           "Mid-Low Wide Forehand", "Mid-Low Wide Backhand", "Low Wide Forehand", "Low Wide Backhand", "Ready"]
BASES = ["Athletic Ready", "Split Step", "Recovery Ready", "Kitchen Neutral", "Dink Base", "Drop Reset Base",
         "Punch Volley Ready", "Dink Volley Ready", "Deep Volley Ready", "Groundstroke Base", "Lob Defense Base",
         "Forehand Lunge", "Backhand Lunge", "Low Scoop Lunge", "Overhead Prep", "Jump Takeoff", "Air Smash",
         "Landing Recovery", "Lateral Shuffle", "Crossover Run", "(Backpedal)", "Decel Plant"]
FLAGS = {"c": "charging", "s": "CONTACT", "f": "finish", "v": "serve", "r": "SPECIAL-REACH"}

def name(table, i): return f"{i:02d} {table[i]}" if 0 <= i < len(table) else str(i)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = sys.argv[1:]
bench = args[0]
only = int(args[1]) if len(args) > 1 else None
def opt(flag, default):
    return float(opts[opts.index(flag) + 1]) if flag in opts else default
t_from, t_to = opt("--from", 0.0), opt("--to", 1e9)
summary = "--summary" in opts
flights = "--flights" in opts

hits = collections.defaultdict(set)
for line in open(f"logs/bench_{bench}.perf.jsonl"):
    r = json.loads(line)
    if r.get("kind") == "note" and r.get("note") == "execution":
        hits[r["data"]["actor"]].add(r["data"]["tick"])

rows = []
for line in gzip.open(f"logs/bench_{bench}.pose.jsonl.gz", "rt"):
    r = json.loads(line)
    rows.append(r)
if not rows or not any(k.startswith("i") for k in rows[-1]):
    sys.exit("no pose info in this trace: rerun the bench (needs PerfMonitor pose info i0..i3)")
t0 = rows[0]["tick"]

players = [only] if only is not None else [0, 1, 2, 3]
if flights:
    # One flight = the ticks one AI player tracked one ball flight id up to its hit.
    tot = collections.Counter(); late = []; flips_per = []; worst = []
    by_charge = collections.defaultdict(list)
    for p in players:
        key = f"i{p}"; seq = []
        for r in rows:
            info = r.get(key)
            if info and len(info) > 6 and info[6]: seq.append((r["tick"], info[0], info[6]))
        for hit in sorted(hits[p]):
            ai_at_hit = next((a for t, s, a in reversed(seq) if t <= hit), None)
            if ai_at_hit is None: continue
            fid = ai_at_hit[4]
            track = [(t, s, a) for t, s, a in seq if t <= hit and a[4] == fid]
            if not track: continue
            pred = [a[0] for _, _, a in track]; shown = [s for _, s, _ in track]
            pf = sum(1 for i in range(1, len(pred)) if pred[i] != pred[i - 1])
            sf = sum(1 for i in range(1, len(shown)) if shown[i] != shown[i - 1])
            # quick back-and-forth: A -> B -> A within 6 ticks (0.2 s)
            bounce = sum(1 for i in range(2, len(pred)) if pred[i] == pred[i - 2] != pred[i - 1])
            last_change = next((hit - track[i][0] for i in range(len(track) - 1, 0, -1) if track[i][1] != track[i - 1][1]), None)
            early = next((s for t, s, _ in reversed(track) if hit - t >= 9), None)  # shown pose 0.3 s before
            tot["hits"] += 1; tot["pred_flips"] += pf; tot["shown_flips"] += sf; tot["back_and_forth"] += bounce
            if early is not None and early != shown[-1]: tot["changed_in_last_0.3s"] += 1
            if last_change is not None: late.append(last_change / 30.0)
            charge = ai_at_hit[3]
            by_charge[STROKES[shown[-1]] if 0 <= shown[-1] < len(STROKES) else shown[-1]].append(charge)
            worst.append((sf, pf, p, (hit - t0) / 30.0, [name(STROKES, x) for x in dict.fromkeys(shown)]))
    n = max(1, tot["hits"])
    print(f"AI hits tracked: {tot['hits']}")
    print(f"  predicted-pose changes per ball: {tot['pred_flips'] / n:.2f}   back-and-forth (A>B>A): {tot['back_and_forth']}")
    print(f"  shown-pose changes per ball:     {tot['shown_flips'] / n:.2f}")
    print(f"  shown pose changed in the last 0.3 s before contact: {tot['changed_in_last_0.3s']} of {tot['hits']}")
    if late: print(f"  last shown-pose change before contact: median {sorted(late)[len(late) // 2]:.2f} s, min {min(late):.2f} s")
    print("  most-changed balls (shown flips, predicted flips, player, time, poses in order):")
    for w in sorted(worst, reverse=True)[:6]: print(f"    {w[0]:2d} {w[1]:2d}  p{w[2]} {w[3]:6.1f}s  {' > '.join(w[4])}")
    print("  charge at contact by pose (min / median / max):")
    for k, v in sorted(by_charge.items(), key=lambda kv: -len(kv[1])):
        v = sorted(v); print(f"    {k:24s} {len(v):3d} hits  {v[0]:.2f} / {v[len(v) // 2]:.2f} / {v[-1]:.2f}")
    sys.exit(0)
for p in players:
    key = f"i{p}"
    if summary:
        time_in = collections.Counter(); at_hit = collections.Counter()
        for r in rows:
            info = r.get(key)
            if not info: continue
            pair = f"{name(STROKES, info[0])}  +  {name(BASES, info[1])} (mix {info[2]:.2f})"
            time_in[pair] += 1
            if r["tick"] in hits[p]: at_hit[pair] += 1
        print(f"== player {p}: {len(hits[p])} hits")
        print("  at contact:")
        for pair, n in at_hit.most_common(): print(f"    {n:3d} x  {pair}")
        print("  time spent (s):")
        for pair, n in time_in.most_common(12): print(f"    {n / 30:5.1f}  {pair}")
        continue
    print(f"== player {p}")
    prev = None
    for r in rows:
        info = r.get(key)
        if not info: continue
        t = (r["tick"] - t0) / 30.0
        if t < t_from or t > t_to: continue
        hit = r["tick"] in hits[p]
        state = (info[0], info[1], info[2], info[3], info[4])
        if state == prev and not hit: continue
        prev = state
        flags = " ".join(FLAGS.get(c, c) for c in info[4])
        phase = f"phase {info[3]}" if info[3] >= 0 else ""
        mark = "  <== HIT" if hit else ""
        print(f"  {t:7.2f}s  {name(STROKES, info[0]):26s} + {name(BASES, info[1]):22s} mix {info[2]:.2f}  {phase:8s} {flags}{mark}")
