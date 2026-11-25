#!/bin/bash
# Build the native library (native/, GDExtension class PickleNative): the macOS dylib the editor
# and benches load, and the iOS static library packaged as xcframeworks for the phone export.
# Usage: tools/build_native.sh [macos|ios|all]   (default all)
# Needs godot-cpp (GODOT_CPP, default: the toolchain folder) built for the same platform:
#   cd $GODOT_CPP && python3 -m SCons platform=<macos|ios> target=template_release arch=arm64 custom_api_file=<api463/extension_api.json>
set -euo pipefail
cd "$(dirname "$0")/../native"
GODOT_CPP=${GODOT_CPP:-$HOME/Documents/Codex/2026-10-15/task/duos-integration/toolchain/godot-cpp}
WHAT=${1:-all}
if [ "$WHAT" = macos ] || [ "$WHAT" = all ]; then
  python3 -m SCons platform=macos target=template_release arch=arm64 -j8
fi
if [ "$WHAT" = ios ] || [ "$WHAT" = all ]; then
  python3 -m SCons platform=ios target=template_release arch=arm64 -j8
  rm -rf bin/libpickle_native.ios.xcframework bin/libgodot-cpp.ios.xcframework
  xcodebuild -create-xcframework -library bin/libpickle_native.ios.a -output bin/libpickle_native.ios.xcframework
  xcodebuild -create-xcframework -library "$GODOT_CPP/bin/libgodot-cpp.ios.template_release.arm64.a" -output bin/libgodot-cpp.ios.xcframework
fi
ls -la bin
