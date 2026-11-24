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
#   END_CHANGE=n  change ends at n points (measure the change-ends sequence)
#   PRESSURE=n    team n hits every rally ball as a full-power drive / smash (defense test)
#   DIFF=n        AI difficulty 0 Easy / 1 Medium / 2 Hard (default 0, the game default)
#   STYLES=a,b,c,d  AI style id per actor 0..3 (0 All-Rounder, 1 Power Attacker, 2 Patient Dinker,
#                 3 Counterpuncher, 4 Lob Tactician; default 0,1,0,2 = the game defaults).
#                 The bench never reads this Mac's saved gameplay settings; the run prints what it used.
#   POSITION_TEAM=n only team n uses the position rules (9 = nobody): positional-play A/B
#   SMART_TEAM=n    only team n uses the AI stamina strategy (9 = nobody)
#   STAMINA_PIN=a:v[,a:v]  hold actor a's stamina at v (0 exhausted, 100 unlimited); others drain
#   OBJ="..."    required: what the run must answer; logged in docs/BENCH_LOG.md (rules: docs/BENCH_RULES.md)
#   KEEP=n        keep the newest n bench runs in logs/ (default 12), delete older ones
#   -> logs/bench_<name>.perf.jsonl, .pose.jsonl.gz (.log only if it had errors).
#   Output is ~5 lines: errors, gameplay (points, how they ended, phase times), top systems,
#   freezes, jitter. Mac FPS is left out: headless fixed-fps numbers say nothing about the phone.
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?name}; SECS=${2:-60}; SEED=${3:-1}
[ -n "${BENCH_CHILD:-}" ] || : "${OBJ:?set OBJ=\"what this bench must answer\" (docs/BENCH_RULES.md)}"
PIN=(--set=gameplay.difficulty=${DIFF:-0})
IFS=, read -r ST0 ST1 ST2 ST3 <<< "${STYLES:-0,1,0,2}"
PIN+=(--set=gameplay.ai_style_self=${ST0:-0} --set=gameplay.ai_style_opponent_one=${ST1:-1}
      --set=gameplay.ai_style_partner=${ST2:-0} --set=gameplay.ai_style_opponent_two=${ST3:-2})
mkdir -p logs
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
"$GODOT" --headless --path . --fixed-fps 60 --quit-after $((SECS * 60)) res://scenes/game.tscn -- \
  $([ "${DESKTOP:-0}" = 1 ] || echo --mobile-runtime) --autoplay --doubles --seed=$SEED $([ -n "${HUMAN:-}" ] && echo --bench-human=$HUMAN) $([ -n "${END_CHANGE:-}" ] && echo --end-change-at=$END_CHANGE) $([ -n "${PRESSURE:-}" ] && echo --pressure-team=$PRESSURE) --viewport=${RES:-720x1280} "${PIN[@]}" $([ -n "${STAMINA_PIN:-}" ] && echo --stamina-pin=$STAMINA_PIN) $([ -n "${POSITION_TEAM:-}" ] && echo --position-team=$POSITION_TEAM) $([ -n "${SMART_TEAM:-}" ] && echo --smart-team=$SMART_TEAM) \
  --perf-out="$PWD/logs/bench_$NAME.perf.jsonl" --spike-ms=${SPIKE_MS:-20} --pose-trace="$PWD/logs/bench_$NAME.pose.jsonl" $([ "${FRAME_LOG:-0}" = 1 ] && echo --frame-log="$PWD/logs/bench_$NAME.frames.jsonl") \
  > "logs/bench_$NAME.log" 2>&1
ERRS=$(grep -cE 'SCRIPT ERROR|Parse Error' "logs/bench_$NAME.log")
echo "[$NAME seed $SEED] script errors: $ERRS"
grep -hE 'SCRIPT ERROR|Parse Error' "logs/bench_$NAME.log" | sort | uniq -c | sort -rn | head -3
[ "$ERRS" = 0 ] && rm -f "logs/bench_$NAME.log"          # only kept when it has errors
gzip -f "logs/bench_$NAME.pose.jsonl"                     # ~5x smaller; pose_diff reads .gz
python3 - "logs/bench_$NAME.perf.jsonl" <<'PY'
import json, sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r.get("note") == "bench_settings":
        d = r["data"]; print(f"Settings: {['Easy', 'Medium', 'Hard'][d['difficulty']]}, styles {' / '.join(d['styles'])} (actors 0-3), accuracy {d['execution_accuracy']}, reaction delay {d['reaction_delay']}"); break
PY
if [ "${VERBOSE:-0}" = 1 ]; then python3 tools/perf_report.py "logs/bench_$NAME.perf.jsonl"
else python3 tools/perf_report.py --short "logs/bench_$NAME.perf.jsonl"; fi
DIFF_LINE=""
if [ -n "${BASE:-}" ]; then
  DIFF_LINE=$(python3 tools/pose_diff.py "logs/bench_$BASE.pose.jsonl.gz" "logs/bench_$NAME.pose.jsonl.gz" | tail -1)
  echo "poses vs $BASE: $DIFF_LINE"
fi
if [ -z "${BENCH_CHILD:-}" ]; then
  python3 tools/perf_report.py --short "logs/bench_$NAME.perf.jsonl" | grep -E "^Points" | python3 tools/bench_log.py name="$NAME" tool=bench \
    obj="$OBJ" seeds="$SEED" ran="$SEED" secs="$SECS" wall="$SECONDS" base="${BASE:+$BASE: $DIFF_LINE}" stop="$([ "$ERRS" = 0 ] || echo "$ERRS script errors")"
fi
# Prune: keep the newest KEEP runs (by their perf log), never the current one or BASE.
ls -t logs/bench_*.perf.jsonl 2>/dev/null | tail -n +$((${KEEP:-12} + 1)) | while read -r old; do
  n=${old#logs/bench_}; n=${n%.perf.jsonl}
  [ "$n" = "$NAME" ] || [ "$n" = "${BASE:-}" ] || rm -f logs/bench_"$n".*
done
