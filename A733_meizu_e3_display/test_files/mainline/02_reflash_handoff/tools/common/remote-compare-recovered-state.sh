#!/bin/sh
set -eu

echo "=== uptime/backlight ==="
cat /proc/uptime
for dev in /sys/class/backlight/backlight0 /sys/class/backlight/sgm37604a; do
	[ -d "$dev" ] || continue
	printf '%s brightness=' "$dev"
	cat "$dev/brightness"
	printf '%s actual=' "$dev"
	cat "$dev/actual_brightness"
done

echo "=== active framebuffer and CRTC progress ==="
if [ -r /sys/kernel/debug/dri/0/state ]; then
	grep -E \
		'^plane|^[[:space:]]+crtc=|^[[:space:]]+fb=|paddr=|^crtc|^[[:space:]]+on:|^[[:space:]]+vsync:' \
		/sys/kernel/debug/dri/0/state
fi

echo "=== mapper ==="
ps -eo pid=,args= | grep '[m]ap-touch-to-dsi.sh' || true
