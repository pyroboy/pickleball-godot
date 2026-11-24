#!/bin/bash
# Drive deterioration bench (docs/PLAYER_FEEL_PLAN.md): team 0 drives every rally ball
# (bench.sh PRESSURE=0) over several seeds, then tools/drive_report.py: drive speed, misses
# and outcome by drive streak and driver stamina, and the defender's reply by its stamina.
# Usage: OBJ="question" tools/drive_bench.sh <name> [seconds=180] ["seeds"="1 2 3"]   (DIFF= passes through)
cd "$(dirname "$0")/.." || exit 1
NAME=${1:?name}; SECS=${2:-180}; SEEDS=${3:-1 2 3}
: "${OBJ:?set OBJ=\"what this bench must answer\" (docs/BENCH_RULES.md)}"
for s in $SEEDS; do
  BENCH_CHILD=1 PRESSURE=0 KEEP=${KEEP:-60} nice -n 10 tools/bench.sh "${NAME}_s$s" "$SECS" "$s" > "logs/bench_${NAME}_s$s.summary.txt" 2>&1 &
done
wait
grep -h "script errors" logs/bench_${NAME}_s*.summary.txt | tr '\n' ' '; echo
python3 tools/drive_report.py --team=0 $(for s in $SEEDS; do echo logs/bench_${NAME}_s$s.perf.jsonl; done) | tee "logs/bench_${NAME}.totals.txt"
head -6 "logs/bench_${NAME}.totals.txt" | python3 tools/bench_log.py name="$NAME" tool=drive_bench obj="$OBJ" seeds="$SEEDS" ran="$SEEDS" \
  secs="$SECS" wall="$SECONDS" why="${WHY:-seeds run in parallel; drive streaks are rare per seed}"
