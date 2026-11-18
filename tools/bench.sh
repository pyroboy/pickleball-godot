#!/bin/bash
# Deterministic headless benchmark: phone-like runtime (no desktop debug systems),
# all four players AI-driven, fixed seed, fixed 60 fps timestep.
# Usage: tools/bench.sh <name> [seconds=60] [seed=1]   (DESKTOP=1: keep desktop-only debug systems)
#   FRAME_LOG=1: also write logs/bench_<name>.frames.jsonl (per-frame scopes)
#   -> logs/bench_<name>.perf.jsonl, logs/bench_<name>.pose.jsonl, prints the report.
# Compare poses: python3 tools/pose_diff.py logs/bench_base.pose.jsonl logs/bench_<name>.pose.jsonl
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
  $([ "${DESKTOP:-0}" = 1 ] || echo --mobile-runtime) --autoplay --doubles --seed=$SEED \
  --perf-out="$PWD/logs/bench_$NAME.perf.jsonl" --spike-ms=${SPIKE_MS:-50} --pose-trace="$PWD/logs/bench_$NAME.pose.jsonl" $([ "${FRAME_LOG:-0}" = 1 ] && echo --frame-log="$PWD/logs/bench_$NAME.frames.jsonl") \
  > "logs/bench_$NAME.log" 2>&1
echo "script errors: $(grep -cE 'SCRIPT ERROR|Parse Error' "logs/bench_$NAME.log")"
grep -hE 'SCRIPT ERROR|Parse Error' "logs/bench_$NAME.log" | sort | uniq -c | head -5
python3 tools/perf_report.py "logs/bench_$NAME.perf.jsonl"
