#!/bin/bash
# The match bench over several seeds (default 1 2 3), one after another at low priority, then the
# totals: points and how they ended, AI hits, and the animation checks (tools/pose_timeline.py
# --swings and --flights) summed over the seeds. One seed is too few for gameplay calls: rally
# lengths swing a lot by seed.
# Usage: tools/bench_seeds.sh <name> [seconds=120] ["seeds"="1 2 3"]
#   -> logs/bench_<name>_s<seed>.* per seed (other bench.sh options pass through: FRAME_LOG, HUMAN...)
cd "$(dirname "$0")/.." || exit 1
NAME=${1:?name}; SECS=${2:-120}; SEEDS=${3:-1 2 3}
[ "$SECS" -ge 10 ] 2>/dev/null || { echo "seconds must be a number >= 10"; exit 1; }
N=$(echo $SEEDS | wc -w | tr -d ' ')
for s in $SEEDS; do
  KEEP=$((12 + 3 * N)) nice -n 19 tools/bench.sh "${NAME}_s$s" "$SECS" "$s" > "logs/bench_${NAME}_s$s.summary.txt" 2>&1
  grep -E "script errors|Points" "logs/bench_${NAME}_s$s.summary.txt" | tr '\n' ' '; echo
done
python3 - "$NAME" $SEEDS <<'EOF'
import re, subprocess, sys, collections, json
name, seeds = sys.argv[1], sys.argv[2:]
tot = collections.Counter(); reasons = collections.Counter(); gaps = []
for s in seeds:
    b = f"{name}_s{s}"
    txt = open(f"logs/bench_{b}.summary.txt").read()
    m = re.search(r"Points (\d+)(?: \(([^)]*)\))?", txt)
    if m:
        tot["points"] += int(m.group(1))
        for part in (m.group(2) or "").split(","):
            if part.strip(): k, v = part.strip().rsplit(" ", 1); reasons[k] += int(v)
    tot["ai_hits"] += sum(1 for l in open(f"logs/bench_{b}.perf.jsonl") if '"ai_launch"' in l)
    sw = subprocess.run(["python3", "tools/pose_timeline.py", b, "--swings"], capture_output=True, text=True).stdout
    fl = subprocess.run(["python3", "tools/pose_timeline.py", b, "--flights"], capture_output=True, text=True).stdout
    def num(pat, t, g=1, cast=int):
        m = re.search(pat, t); return cast(m.group(g)) if m else 0
    tot["hits"] += num(r"^hits (\d+)", sw.replace("\n", "\n"), 1) if sw.startswith("hits") else 0
    tot["snap"] += num(r"snap-back[^:]*: (\d+)", sw)
    tot["windups"] += num(r"wind-ups that reverse: \d+ of (\d+)", sw)
    tot["windup_rev"] += num(r"twice or more: (\d+)", sw)
    tot["flutter"] += num(r"paddle flutter episodes: (\d+)", sw)
    tot["far15"] += num(r"over 15 cm: (\d+)", sw)
    med = re.search(r"median ([\d.]+) cm, worst", sw)
    if med: gaps.append(float(med.group(1)))
    tot["late"] += num(r"last 0.3 s before contact: (\d+)", fl)
    tot["tracked"] += num(r"AI hits tracked: (\d+)", fl)
n = max(1, tot["hits"])
print(f"== {name}: {len(seeds)} seeds")
print(f"  points {tot['points']} ({', '.join(f'{k} {v}' for k, v in reasons.most_common())}) | AI hits {tot['ai_hits']}")
print(f"  contact snap-back {tot['snap']} of {tot['hits']} hits ({100 * tot['snap'] / n:.0f}%) | head-to-ball over 15 cm {tot['far15']}"
      + (f" | median gap per seed {', '.join(f'{g:.1f}' for g in gaps)} cm" if gaps else ""))
print(f"  wind-ups that wobble (reverse twice or more; one reversal is the backswing) {tot['windup_rev']} of {tot['windups']} | paddle flutter episodes {tot['flutter']}"
      f" | pose changed in last 0.3 s {tot['late']} of {tot['tracked']}")
# Animation rules (PASS / FAIL). Limits sit just above today's levels so a regression shows.
errs = sum(int(m) for s in seeds for m in re.findall(r"script errors: (\d+)", open(f"logs/bench_{name}_s{s}.summary.txt").read()))
rules = [
    ("no script errors", errs == 0, f"{errs}"),
    ("pose never switches in the last 0.3 s before contact", tot["late"] == 0, f"{tot['late']}"),
    ("paddle head meets the ball (over 15 cm off on at most 5% of hits)", tot["far15"] <= 0.05 * n, f"{100 * tot['far15'] / n:.1f}%"),
    ("no snap-back at contact (at most 6% of hits)", tot["snap"] <= 0.06 * n, f"{100 * tot['snap'] / n:.1f}%"),
    ("wind-up is one backswing (wobble on at most 30%)", tot["windup_rev"] <= 0.3 * max(1, tot["windups"]), f"{100 * tot['windup_rev'] / max(1, tot['windups']):.0f}%"),
    ("paddle flutter at most 2 episodes per hit", tot["flutter"] <= 2 * n, f"{tot['flutter'] / n:.2f}"),
]
print("  rules:")
for label, ok, val in rules: print(f"    {'PASS' if ok else 'FAIL'}  {label}: {val}")
EOF
