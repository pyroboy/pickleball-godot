#!/bin/bash
# Human-seat perf bench (docs/PERFORMANCE_PLAN.md step 1): fixed seed, headless, fixed 60 fps.
# tools/_human_perf_probe.gd drives the human seat (HIT held while a ball comes in, released
# near it; pulsed to serve), the other three players are AI. Reports the human seat's cost on
# this Mac: ms per second of rally for human.update and the touch-input scopes, and the worst
# frame of each. Timing only: not a gameplay bench, nothing is appended to docs/BENCH_LOG.md.
# Usage: tools/human_seat_bench.sh <name> [seconds=180] [seed=1]   (game seconds; about 1/5 of that in wall time)
#   TOGGLES=human_plan_once=0,touch_on_change=0   PerfToggles for this run (default: all as coded)
#   -> logs/human_seat_<name>.perf.jsonl (.log kept only when it had script errors)
# Before/after: run both back to back on the same tree, e.g.
#   TOGGLES=human_plan_once=0,touch_on_change=0 tools/human_seat_bench.sh off; tools/human_seat_bench.sh on
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?name}; SECS=${2:-180}; SEED=${3:-1}
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
mkdir -p logs
OUT="logs/human_seat_$NAME"
"$GODOT" --headless --path . --fixed-fps 60 -s tools/_human_perf_probe.gd -- \
  --mobile-runtime --doubles --seed=$SEED --hp-seconds=$SECS --viewport=720x1280 \
  ${TOGGLES:+--perf-toggles=$TOGGLES} --perf-out="$PWD/$OUT.perf.jsonl" > "$OUT.log" 2>&1 &
PID=$!
# Watchdog: a broken script (another session mid-edit) floods the log with errors every frame.
while kill -0 $PID 2>/dev/null; do
  if [ "$(grep -cE 'SCRIPT ERROR|Parse Error' "$OUT.log")" -gt 200 ]; then
    kill $PID; wait $PID 2>/dev/null
    echo "[$NAME] stopped: script errors flooding the log"; grep -hE 'Parse Error' -A1 "$OUT.log" | head -4
    head -c 2000000 "$OUT.log" > "$OUT.log.tmp" && mv "$OUT.log.tmp" "$OUT.log"; exit 1
  fi
  sleep 2
done
wait $PID
ERRS=$(grep -cE 'SCRIPT ERROR|Parse Error' "$OUT.log")
echo "[$NAME seed $SEED ${SECS}s] script errors: $ERRS"
grep -hE 'SCRIPT ERROR|Parse Error' "$OUT.log" | sort | uniq -c | sort -rn | head -3
grep -h '^PROBE' "$OUT.log"
[ "$ERRS" = 0 ] && rm -f "$OUT.log"
python3 - "$OUT.perf.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
secs = [r for r in rows if r["kind"] == "sec" and r["state"] == "PLAYING"]
if not secs: sys.exit("no rally seconds recorded")
# Scope row: [ms per frame (mean over the second), worst frame ms, calls per frame].
# Toggles change the game a little, so runs differ in how long HIT is held: compare ms/call
# and calls/s (human.plan per second, human.held_pose per human.set_charge) as well as ms/s.
SCOPES = ["human.update", "human.plan", "human.anticipation", "human.superblocks", "human.pose",
          "human.swing", "human.indicators", "human.set_charge", "human.held_pose", "proc.input_handler",
          "input.charge", "input.aim", "proc.mobile_controls", "draw.mobile_controls", "planner.select"]
frames = sum(r["fps"] for r in secs)   # fixed 60 fps: one frame = 1/60 s of game time
print(f"rally: {frames / 60.0:.0f} s of game time")
print(f"{'scope':22s} {'ms/s':>8s} {'worst ms':>9s} {'calls/s':>8s} {'ms/call':>8s}")
for k in SCOPES:
    v = [(r["scopes"][k], r["fps"]) for r in secs if k in r["scopes"]]
    if not v: continue
    mss = sum(x[0] * n for x, n in v) / frames * 60.0
    cps = sum(x[2] * n for x, n in v) / frames * 60.0
    print(f"{k:22s} {mss:8.2f} {max(x[1] for x, n in v):9.2f} {cps:8.1f} {mss / cps if cps else 0:8.3f}")
seat = ["human.update", "proc.input_handler", "proc.mobile_controls", "draw.mobile_controls"]
tot = sum(r["scopes"].get(k, [0, 0, 0])[0] * r["fps"] for r in secs for k in seat) / frames * 60.0
worst = max(r["scopes"].get(k, [0, 0, 0])[1] for r in secs for k in seat)
print(f"HUMAN SEAT (human.update + input_handler + mobile_controls process + draw): {tot:.1f} ms/s of rally, worst single frame of one scope {worst:.2f} ms")
PY
