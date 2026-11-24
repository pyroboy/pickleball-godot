#!/bin/bash
# The match bench over one or more seeds (default: seed 1), one after another at low priority, then
# the totals: points and how they ended, AI hits, and the animation checks (tools/pose_timeline.py
# --swings and --flights) summed over the seeds. It stops by itself when more seeds can't help
# (script errors, a needed datapoint missing, poses identical to BASE).
# Usage: OBJ="question" tools/bench_seeds.sh <name> [seconds=120] ["seeds"="1"]
#   OBJ="..."   required: what the bench must answer (rules: docs/BENCH_RULES.md)
#   WHY="..."   required with more than one seed: why that many
#   NEED=a,b    perf notes the objective needs: refuses to start when no script records one,
#               stops after a seed that recorded none
#   BASE=<name> compare poses with that run (its _s<seed> run when there is one); stops at the
#               first IDENTICAL seed (no gameplay difference: other seeds would match)
#   ADD=1       keep seeds of this name that already ran, run only the new ones (unchanged code only)
#   SERIAL=1    run the seeds one after another (default: side by side, one process each)
#   -> logs/bench_<name>_s<seed>.* per seed (other bench.sh options pass through: FRAME_LOG, HUMAN...)
#   -> an entry in docs/BENCH_LOG.md
cd "$(dirname "$0")/.." || exit 1
NAME=${1:?name}; SECS=${2:-120}; SEEDS=${3:-1}
[ "$SECS" -ge 10 ] 2>/dev/null || { echo "seconds must be a number >= 10"; exit 1; }
: "${OBJ:?set OBJ=\"what this bench must answer\" (docs/BENCH_RULES.md)}"
N=$(echo $SEEDS | wc -w | tr -d ' ')
[ "$N" -le 1 ] || : "${WHY:?more than one seed needs WHY=\"reason\" (docs/BENCH_RULES.md, section 2)}"
NEEDS=${NEED:-}; NEEDS=${NEEDS//,/ }
for n in $NEEDS; do
  grep -rqF "\"$n\"" scripts || { echo "NOT STARTED: no script records \"$n\". Add the datapoint first."; exit 2; }
done
RAN=""; STOP=""; BASE_NAME=${BASE:-}; BASE_RESULT=""
# Seeds run side by side (one process each), so three seeds take the wall time of one.
# SERIAL=1 runs them one after another instead (then a failed seed stops the rest early).
PIDS=""
if [ "${SERIAL:-0}" != 1 ] && [ "$N" -gt 1 ]; then
  for s in $SEEDS; do
    B="${NAME}_s$s"; SUM="logs/bench_$B.summary.txt"
    [ "${ADD:-0}" = 1 ] && [ -s "logs/bench_$B.perf.jsonl" ] && [ -s "$SUM" ] && continue
    SB=$BASE_NAME; [ -n "$SB" ] && [ -e "logs/bench_${SB}_s$s.pose.jsonl.gz" ] && SB="${SB}_s$s"
    BENCH_CHILD=1 BASE=$SB KEEP=${KEEP:-$((12 + 3 * N))} nice -n 19 tools/bench.sh "$B" "$SECS" "$s" > "$SUM" 2>&1 &
    PIDS="$PIDS $!"
  done
  wait $PIDS
fi
for s in $SEEDS; do
  B="${NAME}_s$s"; SUM="logs/bench_$B.summary.txt"
  if [ "${ADD:-0}" = 1 ] && [ -z "$PIDS" ] && [ -s "logs/bench_$B.perf.jsonl" ] && [ -s "$SUM" ]; then
    RAN="$RAN $s"; echo "seed $s: kept from the earlier run"; continue
  fi
  SB=$BASE_NAME; [ -n "$SB" ] && [ -e "logs/bench_${SB}_s$s.pose.jsonl.gz" ] && SB="${SB}_s$s"
  [ -n "$PIDS" ] || BENCH_CHILD=1 BASE=$SB KEEP=${KEEP:-$((12 + 3 * N))} nice -n 19 tools/bench.sh "$B" "$SECS" "$s" > "$SUM" 2>&1
  RAN="$RAN $s"
  grep -E "script errors|Points|poses vs" "$SUM" | tr '\n' ' '; echo
  grep -q "script errors: 0" "$SUM" || { STOP="seed $s had script errors"; break; }
  for n in $NEEDS; do
    [ "$(grep -cF "\"$n\"" "logs/bench_$B.perf.jsonl")" -gt 0 ] || { STOP="seed $s recorded no \"$n\": the bench can't answer the objective"; break 2; }
  done
  if [ -n "$SB" ]; then
    BASE_RESULT="$BASE_RESULT s$s $(grep -oE "IDENTICAL|DIVERGED" "$SUM" | head -1)"
    grep -q "poses vs.*IDENTICAL" "$SUM" && { STOP="seed $s is IDENTICAL to $SB: no gameplay difference, other seeds would match"; break; }
  fi
done
[ -n "$STOP" ] && echo "STOPPED: $STOP. Recalibrate before another run (docs/BENCH_RULES.md, section 4)."
NEED_COUNTS=""
for n in $NEEDS; do
  c=0; for s in $RAN; do c=$((c + $(grep -cF "\"$n\"" "logs/bench_${NAME}_s$s.perf.jsonl"))); done
  NEED_COUNTS="$NEED_COUNTS$n $c, "
done
SEEDS_ALL=$SEEDS; SEEDS=$RAN
python3 - "$NAME" $SEEDS > "logs/bench_${NAME}.totals.txt" <<'EOF'
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
    tot["reflex"] += num(r"first commitment in the last 0.3 s[^:]*: (\d+)", fl)
    tot["tracked"] += num(r"AI hits tracked: (\d+)", fl)
n = max(1, tot["hits"])
print(f"== {name}: {len(seeds)} seeds")
print(f"  points {tot['points']} ({', '.join(f'{k} {v}' for k, v in reasons.most_common())}) | AI hits {tot['ai_hits']}")
print(f"  contact snap-back {tot['snap']} of {tot['hits']} hits ({100 * tot['snap'] / n:.0f}%) | head-to-ball over 15 cm {tot['far15']}"
      + (f" | median gap per seed {', '.join(f'{g:.1f}' for g in gaps)} cm" if gaps else ""))
print(f"  wind-ups that wobble (reverse twice or more; one reversal is the backswing) {tot['windup_rev']} of {tot['windups']} | paddle flutter episodes {tot['flutter']}"
      f" | pose changed in last 0.3 s {tot['late']} of {tot['tracked']} (+{tot['reflex']} reflex blocks on balls inside the reaction delay)")
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
cat "logs/bench_${NAME}.totals.txt"
grep -vE "^ +PASS|rules:" "logs/bench_${NAME}.totals.txt" | python3 tools/bench_log.py name="$NAME" tool=bench_seeds obj="$OBJ" \
  seeds="$SEEDS_ALL" ran="$RAN" secs="$SECS" why="${WHY:-}" wall="$SECONDS" need="${NEED_COUNTS%, }" \
  base="${BASE_NAME:+$BASE_NAME:$BASE_RESULT}" stop="$STOP"
