#!/bin/bash
# Capture poses in the mobile pose editor preview (stages, paddle trace, ghosts) plus body metrics,
# with before/after against a git ref, in ONE Godot run.
# Usage: tools/pose_review.sh s00 [b11 s10 ...] [--base REF]   (REF default HEAD; --base none = no compare)
#        tools/pose_review.sh all
# Output: logs/pose_review/  <key>_<view>.png sheets (rows = stages, cols = before | after)
#         and a metrics table printed here (also logs/pose_review/report.txt).
set -uo pipefail
cd "$(dirname "$0")/.."
BASE=HEAD; IDS=()
while [ $# -gt 0 ]; do
  case "$1" in --base) BASE=$2; shift 2;; *) IDS+=("$1"); shift;; esac
done
[ ${#IDS[@]} -gt 0 ] || { echo "usage: tools/pose_review.sh s00 [b11 ...] [--base REF|none]"; exit 1; }
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
[ -x "${GODOT:-}" ] || { echo "Godot not found, set GODOT=/path/to/Godot"; exit 1; }
OUT="$PWD/logs/pose_review"; rm -rf "$OUT"; mkdir -p "$OUT/raw" "$OUT/before/postures" "$OUT/before/base_poses"
ONLY=""; [ "${IDS[0]}" = all ] || ONLY="--pose-only=$(IFS=,; echo "${IDS[*]}")"
BEFORE=""
if [ "$BASE" != none ]; then
  # Copy each changed pose file from REF so the run captures it as "before".
  for f in $(git diff --name-only "$BASE" -- data/postures data/base_poses) ; do
    key=$(basename "$f" | cut -d_ -f1); pre=s; [[ $f == data/base_poses/* ]] && pre=b
    if [ -z "$ONLY" ] || [[ ",${IDS[*]// /,}," == *",$pre$key,"* ]]; then
      git show "$BASE:$f" > "$OUT/before/${f#data/}" 2>/dev/null && BEFORE="--pose-before=$OUT/before"
    fi
  done
fi
"$GODOT" --path . --resolution 780x1400 res://scenes/game.tscn -- --pose-shots="$OUT/raw" $ONLY $BEFORE \
  > "$OUT/godot.log" 2>&1
grep -hE 'SCRIPT ERROR|Parse Error' "$OUT/godot.log" | sort | uniq -c | head -5
python3 tools/pose_review.py "$OUT" | tee "$OUT/report.txt"
