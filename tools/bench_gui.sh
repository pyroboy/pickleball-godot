#!/bin/bash
# Multi-seed bench in a small window (400x200, centred): bench label, elapsed and
# remaining time, overall bar, one bar per seed, console log, report at the end.
# Usage: tools/bench_gui.sh <name> [seconds=300] [seeds=1-6] [jobs=3]
# Closing the window stops the bench. Logs: logs/bench_<name><seed>.perf.jsonl
cd "$(dirname "$0")/.."
NAME=${1:?name}; SECS=${2:-300}; SEEDS=${3:-1-6}; JOBS=${4:-3}
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
[ -x "${GODOT:-}" ] || { echo "Godot not found, set GODOT=/path/to/Godot"; exit 1; }
export GODOT
exec "$GODOT" --path tools/bench_window -- --root="$PWD" --name="$NAME" --seconds="$SECS" --seeds="$SEEDS" --jobs="$JOBS" ${SHOT:+--shot="$SHOT"}
