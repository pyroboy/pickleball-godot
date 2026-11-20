#!/bin/bash
# Motion bench: one player walks a fixed course (stand, walk, run, stop, backpedal, shuffle,
# diagonal) on a frozen court: no AI, ball or scoring. About 5-10 s. Measures the pixel-card
# motion (arm swing, shoulder turn, step timing, hand pops) and records the gameplay joints.
# Usage: tools/motion_bench.sh <name> [base_name]
#   base_name   compare with logs/motion_bench/<base_name>.json (per-segment changes, and
#               gameplay joints IDENTICAL / DIVERGED: IDENTICAL = the change is visual only)
#   ACTOR=n     which player walks the course (default 0)
#   PICKLEBALL_CARD_MOTION=0   card motion off (A/B)
# -> logs/motion_bench/<name>.json (+ .log only when it had script errors)
# Use tools/bench.sh instead when the change can alter gameplay (shots, ball, AI, contact).
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?name}; BASE=${2:-}
mkdir -p logs/motion_bench
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
OUT="$PWD/logs/motion_bench/$NAME.json"
LOG="logs/motion_bench/$NAME.log"
rm -f "$OUT"
"$GODOT" --headless --path . --fixed-fps 60 -s tools/motion_bench.gd -- --mobile-runtime --autoplay --doubles \
  --seed=1 --viewport=720x1280 --mb-out="$OUT" --mb-actor=${ACTOR:-0} > "$LOG" 2>&1
ERRS=$(grep -cE 'SCRIPT ERROR|Parse Error' "$LOG")
echo "[$NAME] script errors: $ERRS"
grep -hE 'SCRIPT ERROR|Parse Error' "$LOG" | sort | uniq -c | sort -rn | head -3
[ "$ERRS" = 0 ] && rm -f "$LOG"
[ -f "$OUT" ] || { echo "no output (see $LOG)"; exit 1; }
if [ -n "$BASE" ]; then python3 tools/motion_bench_report.py "$OUT" "$PWD/logs/motion_bench/$BASE.json"
else python3 tools/motion_bench_report.py "$OUT"; fi
