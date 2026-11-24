#!/bin/bash
# Record an all-AI doubles match and cut the best rallies into portrait clips for
# short-form video (TikTok / Reels / Shorts). Uses Godot's movie writer, so the
# video is a smooth 60 fps whatever the Mac's speed; a game window opens while it runs.
# Usage: tools/record_clips.sh <name> [seconds=180] [seed=1] [top=3]
#   DIFF=n      AI difficulty 0 Easy / 1 Medium / 2 Hard (default 2: longer rallies)
#   MAX=n       longest clip in seconds (default 40; longer rallies keep their ending)
#   MIN_SHOTS=n skip rallies shorter than this (default 6)
#   KEEP_RAW=1  keep the full recording (logs/clips/<name>_full.avi, large)
#   -> logs/clips/<name>_<rank>_<shots>shots.mp4 (1080x1920, H.264 + AAC)
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?name}; SECS=${2:-180}; SEED=${3:-1}; TOP=${4:-3}
OUT=logs/clips; mkdir -p "$OUT"
RAW="$PWD/$OUT/${NAME}_full.avi"; PERF="$PWD/$OUT/$NAME.perf.jsonl"
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)"; exit 1; }
"$GODOT" --path . --write-movie "$RAW" --fixed-fps 60 --resolution 720x1280 --quit-after $((SECS * 60)) \
  res://scenes/game.tscn -- --mobile-runtime --autoplay --doubles --seed=$SEED \
  --set=gameplay.difficulty=${DIFF:-2} --perf-out="$PERF" > "$OUT/$NAME.log" 2>&1
[ -s "$RAW" ] || { echo "no recording written; see $OUT/$NAME.log"; exit 1; }
python3 - "$PERF" "$RAW" "$OUT/$NAME" "$TOP" "${MAX:-40}" "${MIN_SHOTS:-6}" <<'PY'
import json, subprocess, sys
perf, raw, stem, top, max_len, min_shots = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6])
HZ = 30.0  # physics ticks per second; the movie runs at a fixed step, so tick / HZ is video time
serve, rallies = None, []
for line in open(perf):
    r = json.loads(line); d = r.get("data", {})
    if r.get("event") == "state" and d.get("to") == "SERVING": serve = d["tick"]
    elif r.get("note") == "point_ending" and serve is not None:
        rallies.append((d.get("shots", 0), serve / HZ, d["tick"] / HZ, d.get("reason", "")))
dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", raw],
                           capture_output=True, text=True).stdout or 0)
best = sorted([x for x in rallies if x[0] >= min_shots and x[2] + 1.0 < dur], reverse=True)[:top]
print(f"recorded {dur:.0f} s, {len(rallies)} points; cutting {len(best)} clips")
for i, (shots, t0, t1, reason) in enumerate(best, 1):
    end = min(t1 + 2.5, dur)                   # keep the point-won moment
    start = max(t0 - 0.5, end - max_len, 0.0)  # long rally: keep the ending
    out = f"{stem}_{i}_{shots}shots.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", f"{start:.2f}", "-t", f"{end - start:.2f}", "-i", raw,
                    "-vf", "scale=1080:1920:flags=lanczos", "-c:v", "libx264", "-crf", "18", "-preset", "medium",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", out], check=True)
    print(f"  {out}  {end - start:.1f} s  {shots} shots  ended {reason}")
PY
[ "${KEEP_RAW:-0}" = 1 ] || rm -f "$RAW"
