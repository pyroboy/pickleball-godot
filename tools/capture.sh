#!/bin/bash
# Screenshots of an autoplay doubles match at chosen times (windowed run, real renderer).
# Usage: tools/capture.sh <name> [times=4,9,15] [seed=1]
#   RES=WxH   window size (default 590x1278 = half an iPhone 15 Pro screen)
#   HIDE_UI=1 hide UI layers in the shots
#   -> logs/captures/<name>/frame_<sec>.png
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?name}; TIMES=${2:-4,9,15}; SEED=${3:-1}
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
OUT="$PWD/logs/captures/$NAME"; rm -rf "$OUT"; mkdir -p "$OUT"
LAST=$(echo "$TIMES" | tr ',' '\n' | sort -n | tail -1)
RES=${RES:-590x1278}
"$GODOT" --path . --resolution "$RES" --quit-after $(( (${LAST%.*} + 10) * 300 )) res://scenes/game.tscn -- \
  --mobile-runtime --autoplay --doubles --seed=$SEED --perf-out="$OUT/perf.jsonl" \
  --capture-at="$TIMES" --capture-out="$OUT" $([ "${HIDE_UI:-0}" = 1 ] && echo --capture-hide-ui) > "$OUT/godot.log" 2>&1
echo "[$NAME] $(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') shots in logs/captures/$NAME, script errors: $(grep -cE 'SCRIPT ERROR|Parse Error' "$OUT/godot.log")"
