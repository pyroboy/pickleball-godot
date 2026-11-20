#!/bin/bash
# Desktop Pose Studio: starts Godot windowed (maximized) with the game scene and the
# --pose-studio link, waits until the studio answers on the TCP port, prints
# 'Pose Studio ready'. Ctrl+C asks the studio to quit (link 'quit': it asks about unsaved poses
# in the window); a second Ctrl+C kills Godot. No server: the studio is the Godot window.
# Usage: tools/pose_studio.sh [--port 8766] [--window max|full]
# Log: logs/pose_studio_godot.log. Spec: docs/POSE_STUDIO_SPEC.md; link: tools/pose_studio/PROTOCOL.md.
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
GPORT=8766
WINDOW=max
while [ $# -gt 0 ]; do
  case "$1" in
    --port|--godot-port) GPORT="$2"; shift 2 ;;
    --window) WINDOW="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done
mkdir -p logs
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
[ -x "${GODOT:-}" ] || { echo "Godot not found, set GODOT=/path/to/Godot"; exit 1; }

if python3 -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1',$GPORT))==0 else 1)"; then
  echo "port $GPORT is already in use (another studio running?)"; exit 1
fi

GPID=""
cleanup() {
  trap - INT TERM EXIT
  [ -n "$GPID" ] && kill "$GPID" 2>/dev/null
  { wait; } 2>/dev/null
  echo "Pose Studio stopped."
}
QUITTING=0
on_int() {
  if [ "$QUITTING" = 1 ] || [ -z "$GPID" ]; then cleanup; exit 0; fi
  QUITTING=1
  if python3 - "$GPORT" <<'PY'
import json, socket, sys
try:
    with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=2) as s:
        s.settimeout(10)
        s.sendall(b'{"id": 1, "cmd": "quit"}\n')
        line = s.makefile("rb").readline()
except OSError:
    sys.exit(1)
if not line:
    sys.exit(0)   # quit at once: Godot closed the link
r = json.loads(line)
if not r.get("ok"):
    sys.exit(1)
if r.get("unsaved"):
    print("Unsaved poses: %s. Answer Save all / Discard / Cancel in the studio window "
          "(Ctrl+C again kills Godot and loses them)." % ", ".join(r["unsaved"]), flush=True)
PY
  then :; else cleanup; exit 0; fi
}
trap on_int INT
trap 'cleanup; exit 0' TERM
trap cleanup EXIT

"$GODOT" --path "$ROOT" res://scenes/game.tscn -- --pose-studio="$GPORT" --studio-window="$WINDOW" \
  > logs/pose_studio_godot.log 2>&1 &
GPID=$!

# Wait for the link to answer ping with ready: true (studio and its engine open). Up to 90 s.
python3 - "$GPORT" "$GPID" <<'PY'
import json, os, socket, sys, time
port, pid = int(sys.argv[1]), int(sys.argv[2])
t0 = time.time()
while time.time() - t0 < 90:
    try:
        os.kill(pid, 0)
    except OSError:
        print("Godot exited; see logs/pose_studio_godot.log", flush=True); sys.exit(1)
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2) as s:
            s.settimeout(30)
            s.sendall(b'{"id": 1, "cmd": "ping"}\n')
            line = s.makefile("rb").readline()
        if json.loads(line).get("ready"):
            sys.exit(0)
    except (OSError, ValueError):
        pass
    time.sleep(0.5)
print("timed out waiting for the studio; see logs/pose_studio_godot.log", flush=True)
sys.exit(1)
PY
if [ $? -ne 0 ]; then exit 1; fi
if grep -q "studio ready" logs/pose_studio_godot.log; then
  echo "Pose Studio ready (link 127.0.0.1:$GPORT; Ctrl+C asks the studio to quit)"
else
  echo "Pose Studio ready (link-only mode: studio script missing; 127.0.0.1:$GPORT; Ctrl+C asks the studio to quit)"
fi
# wait returns early when Ctrl+C runs on_int; keep waiting while Godot is alive (it may be
# showing the unsaved-poses dialog).
while kill -0 "$GPID" 2>/dev/null; do wait "$GPID"; done
GPID=""
echo "Godot ended; see logs/pose_studio_godot.log"
