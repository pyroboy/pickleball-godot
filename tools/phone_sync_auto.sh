#!/bin/bash
# Background phone sync every 10 minutes: --loop in a terminal tab (works with the repo in
# ~/Documents), or a macOS LaunchAgent (--install; needs Full Disk Access for /bin/bash, since
# macOS blocks background jobs from ~/Documents).
# Each run checks that the iPhone is reachable (devicectl, ~0.1 s), then runs
# tools/pose_studio/phone_sync.py --auto, which applies new Pose Studio saves / notes / ratings and
# pushes back only when something changed. Nothing is committed.
# Log (only runs that did something, plus errors): logs/phone_sync.log
#
# Usage: tools/phone_sync_auto.sh             one poll (what the agent runs)
#        tools/phone_sync_auto.sh --loop      poll every 10 min until Ctrl-C (terminal tab)
#        tools/phone_sync_auto.sh --install   start polling (every 10 min, and at login)
#        tools/phone_sync_auto.sh --uninstall stop polling
#        tools/phone_sync_auto.sh --status    is it installed, last log lines
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
LABEL=com.arjostyle.pickleball.phonesync
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DEVICE=00008130-001675341460001C
INTERVAL=600
LOG="$ROOT/logs/phone_sync.log"

case "${1:-}" in
--loop)
	echo "Phone sync: polling every $((INTERVAL / 60)) min (Ctrl-C stops). Synced runs go to logs/phone_sync.log"
	while true; do
		"$ROOT/tools/phone_sync_auto.sh"
		[ -f "$LOG" ] && N=$(wc -l < "$LOG") && [ "$N" != "${LAST:-}" ] && [ -n "${LAST:-}" ] && tail -n $((N - LAST)) "$LOG"
		LAST=$( [ -f "$LOG" ] && wc -l < "$LOG" || echo 0 )
		echo "$(date '+%H:%M') checked"
		sleep $INTERVAL
	done;;
--install)
	mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/logs"
	cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/tools/phone_sync_auto.sh</string></array>
	<key>StartInterval</key><integer>$INTERVAL</integer>
	<key>RunAtLoad</key><true/>
	<key>ProcessType</key><string>Background</string>
	<key>LowPriorityIO</key><true/>
	<key>Nice</key><integer>10</integer>
	<key>StandardOutPath</key><string>$ROOT/logs/phone_sync.agent.log</string>
	<key>StandardErrorPath</key><string>$ROOT/logs/phone_sync.agent.log</string>
</dict>
</plist>
EOF
	launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
	launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "Phone sync polling every $((INTERVAL / 60)) min. Log: logs/phone_sync.log"
	exit $?;;
--uninstall)
	launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
	rm -f "$PLIST"; echo "Phone sync polling stopped."
	exit 0;;
--status)
	launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 && echo "installed (every $((INTERVAL / 60)) min)" || echo "not installed"
	[ -f "$LOG" ] && tail -5 "$LOG"
	exit 0;;
esac

# One poll. Skip if another poll (or a manual sync through this script) is still running.
LOCK="$ROOT/logs/.phone_sync.lock"
mkdir -p "$ROOT/logs"
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK"' EXIT
# Phone not reachable (asleep, away, Wi-Fi off): nothing to do.
/usr/bin/xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -qE "available|connected" || exit 0
OUT=$(/usr/bin/python3 "$ROOT/tools/pose_studio/phone_sync.py" --auto --device "$DEVICE" 2>&1)
[ -n "$OUT" ] && printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M')" "$OUT" | sed '2,$s/^/                  /' >> "$LOG"
exit 0
