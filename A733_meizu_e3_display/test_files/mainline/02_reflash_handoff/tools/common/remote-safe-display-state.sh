#!/bin/sh
set -eu

echo "=== identity ==="
uname -a
cat /proc/uptime
cat /proc/sys/kernel/random/boot_id

echo "=== mapper (must remain absent) ==="
ps -eo pid=,comm=,args= | grep '[m]ap-touch-to-dsi.sh' || true

echo "=== backlight sysfs ==="
for dev in /sys/class/backlight/*; do
	[ -d "$dev" ] || continue
	echo "-- $dev"
	for attr in brightness actual_brightness max_brightness bl_power type; do
		[ -r "$dev/$attr" ] && printf '%s=' "$attr" && cat "$dev/$attr"
	done
done

echo "=== sgm37604a live registers (read only) ==="
for reg in 0x10 0x11 0x19 0x1a 0x1b 0x1f; do
	printf '%s=' "$reg"
	i2cget -f -y 0 0x36 "$reg" 2>&1 || true
done

echo "=== current display/touch faults ==="
journalctl -b 0 -k --no-pager -q -o short-monotonic |
	grep -E -i \
		'sunxi_de_atomic_flush|PageTable Invalid|Bug is in DE|SUNXI DRM DEBUG|DE-[01] exception|sec_ts.*(unknown event|Time Over|i2c|fail|error)' ||
	true

echo "=== current event counts ==="
for pattern in \
	'sunxi_de_atomic_flush timeout' \
	'PageTable Invalid' \
	'Bug is in DE' \
	'drm hdmi detect' \
	'sec_ts.*unknown event'; do
	printf '%s: ' "$pattern"
	journalctl -b 0 -k --no-pager -q |
		grep -E -i -c "$pattern" ||
		true
done

echo "=== DRM atomic state (read only; no connector reprobe) ==="
for state in /sys/kernel/debug/dri/0/state /sys/kernel/debug/dri/1/state; do
	[ -r "$state" ] || continue
	echo "-- $state"
	cat "$state"
done

echo "=== saved KDE KScreen files ==="
if [ -d /home/radxa/.local/share/kscreen ]; then
	find /home/radxa/.local/share/kscreen -maxdepth 2 -type f -print |
		while IFS= read -r file; do
			echo "-- $file"
			sed -n '1,240p' "$file"
		done
else
	echo "no KScreen directory"
fi

echo "=== pointer input devices ==="
grep -E -A 6 -B 2 \
	'Name=.*(mouse|Mouse|YICHIP|SEC|sec|touch|Touch)' \
	/proc/bus/input/devices ||
	true
