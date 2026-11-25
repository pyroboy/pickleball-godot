#!/bin/bash
# Pull the iPhone's newest perf log, keep it, and print its budget lines and the Log table row
# of docs/PERFORMANCE_PLAN.md.
# Usage: [STEP=0b] [BUILD=109] tools/phone_perf.sh [which=perf.jsonl]
#   which: perf.jsonl (the running / last session) or perf.1.jsonl ... perf.5.jsonl (older ones;
#          the game keeps the last five, rotated at each launch)
#   -> logs/phone/<YYYYmmdd-HHMMSS>_<which>
cd "$(dirname "$0")/.." || exit 1
DEVICE=${DEVICE:-00008130-001675341460001C}
WHICH=${1:-perf.jsonl}
mkdir -p logs/phone
OUT="logs/phone/$(date +%Y%m%d-%H%M%S)_$WHICH"
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier com.arjomagno.arjostylepickleball.ios --source "Documents/$WHICH" \
  --destination "$OUT" > /dev/null || { echo "pull failed (phone unlocked and connected?)"; exit 1; }
[ -s "$OUT" ] || { echo "pulled an empty file: $OUT"; exit 1; }
echo "kept $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
python3 tools/perf_report.py --budget "$OUT"
echo "Log row (docs/PERFORMANCE_PLAN.md):"
python3 tools/perf_report.py --row "$OUT"
