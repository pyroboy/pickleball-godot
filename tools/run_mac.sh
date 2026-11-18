#!/bin/bash
# Run the game on this Mac in a window. Output goes to logs/game.log.
# Usage: tools/run_mac.sh [--phone] [res://scenes/some_scene.tscn]
#   --phone  runs like the iPhone build (desktop-only debug systems off)
# Then:  tools/game_errors.sh   (deduplicated error summary)
cd "$(dirname "$0")/.."
mkdir -p logs
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
[ -x "${GODOT:-}" ] || { echo "Godot not found, set GODOT=/path/to/Godot"; exit 1; }
EXTRA=()
if [ "${1:-}" = "--phone" ]; then shift; EXTRA=(-- --mobile-runtime); fi
"$GODOT" --path . "$@" "${EXTRA[@]}" > logs/game.log 2>&1 &
echo "running (pid $!), log: logs/game.log"
