#!/bin/bash
# Summarise errors from the running game's log (deduplicated, counted).
cd "$(dirname "$0")/.."
grep -E 'SCRIPT ERROR|Parse Error|ERROR:|WARNING:' logs/game.log 2>/dev/null | sort | uniq -c | sort -rn | head -${1:-15}
