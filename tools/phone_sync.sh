#!/bin/bash
# Phone Pose Studio -> repo: pull the iPhone app's saves, notes and star ratings (xcrun devicectl,
# cable or Wi-Fi pairing), apply them with tools/pose_notes.py like the desktop studio does, and
# push the result back to the phone. Nothing is committed. Details: tools/pose_studio/phone_sync.py
# Usage: tools/phone_sync.sh [--dry-run] [--device UDID]
cd "$(dirname "$0")/.." || exit 1
exec python3 tools/pose_studio/phone_sync.py "$@"
