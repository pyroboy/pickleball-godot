#!/bin/bash
# Deterministic headless benchmark: phone-like runtime (no desktop debug systems),
# all four players AI-driven, fixed seed, fixed 60 fps timestep (runs ~5x real time).
# Usage: tools/bench.sh <name> [seconds=60] [seed=1]
#   DESKTOP=1     keep desktop-only debug systems
#   FRAME_LOG=1   also write logs/bench_<name>.frames.jsonl (per-frame positions, events)
#   BASE=<name>   compare poses with logs/bench_<name>.pose.jsonl (one line: IDENTICAL / DIVERGED)
#   VERBOSE=1     full perf report instead of the short one
#   SPIKE_MS=n   freeze threshold (default 20: the Mac runs ~2.5x the phone, so 20 ms here ~ 50 ms there)
#   RES=WxH       viewport (default 720x1280 portrait, the phone's camera path)
#   HUMAN=n       coordination treats actor n as a human partner (still AI-driven)
#   PRESSURE=n    team n hits every rally ball as a full-power drive / smash (defense test)
#   KEEP=n        keep the newest n bench runs in logs/ (default 12), delete older ones
#   -> logs/bench_<name>.perf.jsonl, .pose.jsonl.gz (.log only if it had errors).
#   Output is ~5 lines: errors, gameplay (points, how they ended, phase times), top systems,
#   freezes, jitter. Mac FPS is left out: headless fixed-fps numbers say nothing about the phone.
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?name}; SECS=${2:-60}; SEED=${3:-1}
mkdir -p logs
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
"$GODOT" --headless --path . --fixed-fps 60 --quit-after $((SECS * 60)) res://scenes/game.tscn -- \
  $([ "${DESKTOP:-0}" = 1 ] || echo --mobile-runtime) --autoplay --doubles --seed=$SEED $([ -n "${HUMAN:-}" ] && echo --bench-human=$HUMAN) $([ -n "${PRESSURE:-}" ] && echo --pressure-team=$PRESSURE) --viewport=${RES:-720x1280} \
  --perf-out="$PWD/logs/bench_$NAME.perf.jsonl" --spike-ms=${SPIKE_MS:-20} --pose-trace="$PWD/logs/bench_$NAME.pose.jsonl" $([ "${FRAME_LOG:-0}" = 1 ] && echo --frame-log="$PWD/logs/bench_$NAME.frames.jsonl") \
  > "logs/bench_$NAME.log" 2>&1
ERRS=$(grep -cE 'SCRIPT ERROR|Parse Error' "logs/bench_$NAME.log")
echo "[$NAME seed $SEED] script errors: $ERRS"
grep -hE 'SCRIPT ERROR|Parse Error' "logs/bench_$NAME.log" | sort | uniq -c | sort -rn | head -3
[ "$ERRS" = 0 ] && rm -f "logs/bench_$NAME.log"          # only kept when it has errors
gzip -f "logs/bench_$NAME.pose.jsonl"                     # ~5x smaller; pose_diff reads .gz
if [ "${VERBOSE:-0}" = 1 ]; then python3 tools/perf_report.py "logs/bench_$NAME.perf.jsonl"
else python3 tools/perf_report.py --short "logs/bench_$NAME.perf.jsonl"; fi
if [ -n "${BASE:-}" ]; then
  echo "poses vs $BASE: $(python3 tools/pose_diff.py "logs/bench_$BASE.pose.jsonl.gz" "logs/bench_$NAME.pose.jsonl.gz" | tail -1)"
fi
# Prune: keep the newest KEEP runs (by their perf log), never the current one or BASE.
ls -t logs/bench_*.perf.jsonl 2>/dev/null | tail -n +$((${KEEP:-12} + 1)) | while read -r old; do
  n=${old#logs/bench_}; n=${n%.perf.jsonl}
  [ "$n" = "$NAME" ] || [ "$n" = "${BASE:-}" ] || rm -f logs/bench_"$n".*
done
