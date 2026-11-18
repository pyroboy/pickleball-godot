#!/bin/bash
# Export game pack -> build -> install -> launch in iOS Simulator.
# Prints one line per step; full output goes to logs/.  Usage: tools/run_sim.sh [--no-export]
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
BUNDLE=com.arjomagno.arjostylepickleball.ios
PROJ=build/ios/ArjostylePickleball.xcodeproj

# --- Godot binary ---
if [ -z "${GODOT:-}" ]; then
  for c in "$(command -v godot 2>/dev/null)" /Applications/Godot.app/Contents/MacOS/Godot \
           "$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi

fail() { echo "FAIL: $1 (see $2)"; grep -E 'ERROR|error:' "$2" | head -5; exit 1; }

# --- 1. export pack ---
if [ "${1:-}" != "--no-export" ]; then
  [ -x "${GODOT:-}" ] || { echo "FAIL: Godot not found, set GODOT=/path/to/Godot"; exit 1; }
  "$GODOT" --headless --path . --export-pack iPhone build/ios/ArjostylePickleball.pck > logs/export.log 2>&1 \
    || fail "export" logs/export.log
  echo "export ok ($(grep -cE 'SCRIPT ERROR|Parse Error' logs/export.log) script errors)"
fi

# --- 2. simulator ---
UDID=$(xcrun simctl list devices booted -j | python3 -c "import json,sys;d=[x for v in json.load(sys.stdin)['devices'].values() for x in v];print(d[0]['udid'] if d else '')")
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys;d=[x for k,v in json.load(sys.stdin)['devices'].items() if 'iOS' in k for x in v if x['name'].startswith('iPhone')];print(d[-1]['udid'] if d else '')")
  [ -n "$UDID" ] || { echo "FAIL: no iPhone simulator available"; exit 1; }
  xcrun simctl boot "$UDID" >/dev/null 2>&1; open -a Simulator
fi
echo "simulator $UDID"

# --- 3. build ---
xcodebuild -project "$PROJ" -scheme ArjostylePickleball -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath build/DerivedData-sim CODE_SIGNING_ALLOWED=NO -quiet \
  > logs/xcodebuild-sim.log 2>&1 || fail "xcodebuild" logs/xcodebuild-sim.log
APP=build/DerivedData-sim/Build/Products/Release-iphonesimulator/ArjostylePickleball.app
echo "build ok"

# --- 4. install + launch (game output -> logs/game.log) ---
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || exit 1
xcrun simctl launch --terminate-running-process --stdout="$PWD/logs/game.log" --stderr="$PWD/logs/game.log" "$UDID" "$BUNDLE" >/dev/null \
  && echo "launched. Errors: tools/game_errors.sh"
