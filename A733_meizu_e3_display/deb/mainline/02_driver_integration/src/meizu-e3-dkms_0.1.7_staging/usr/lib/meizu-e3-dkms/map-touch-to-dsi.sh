#!/bin/sh

# Keep the phone touchscreen attached to the DSI panel instead of the full
# X11 desktop.  xinput computes the correct transformation from xrandr, so
# this also handles HDMI hotplug and display-position changes.

TOUCH_NAME="Samsung Electronics Touchscreen 1223"
OUTPUT_NAME="DSI-1"

[ "${XDG_SESSION_TYPE:-x11}" = "x11" ] || exit 0
command -v xinput >/dev/null 2>&1 || exit 0
command -v xrandr >/dev/null 2>&1 || exit 0

last_state=

while :; do
	layout=$(
		xrandr --query 2>/dev/null |
			awk '$2 == "connected" || $2 == "disconnected" {
				print $1, $2, $3
			}'
	)
	device_id=$(xinput list --id-only "$TOUCH_NAME" 2>/dev/null | head -n 1)
	state="${layout}|${device_id}"

	if [ "$state" != "$last_state" ]; then
		if [ -n "$device_id" ] &&
		   xrandr --query 2>/dev/null |
			grep -q "^${OUTPUT_NAME}[[:space:]]connected"; then
			xinput map-to-output "$device_id" "$OUTPUT_NAME" >/dev/null 2>&1 || true
		fi
		last_state=$state
	fi

	sleep 2
done
