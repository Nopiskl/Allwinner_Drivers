#!/bin/sh
set -eu

echo "=== IDENTITY ==="
uname -a
printf 'boot_id='
cat /proc/sys/kernel/random/boot_id
printf 'uptime='
cat /proc/uptime
printf 'cmdline='
cat /proc/cmdline
echo "-- os-release"
cat /etc/os-release
for file in /etc/radxa_image_fingerprint /etc/radxa_apt_snapshot; do
	[ -r "$file" ] || continue
	echo "-- $file"
	sed -n '1,200p' "$file"
done

echo "=== KERNEL PACKAGES ==="
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
	'linux-image-*a733' 'linux-headers-*a733' 2>/dev/null ||
	true
echo "-- apt cached policy"
apt-cache policy linux-image-radxa-a733 linux-headers-radxa-a733 2>/dev/null ||
	true
echo "-- header trees"
find /usr/src -maxdepth 1 -type d -name '*a733*' -print 2>/dev/null ||
	true

echo "=== CUSTOM PACKAGE/DKMS RESIDUE ==="
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
	'meizu-e3*' 2>/dev/null ||
	true
if command -v dkms >/dev/null 2>&1; then
	dkms status || true
else
	echo "dkms command not installed"
fi
lsmod |
	grep -E '(^| )(sec_ts|sgm37604a)( |$)' ||
	true

echo "=== BOOT CONFIG FILES ==="
find /boot -maxdepth 3 -type f \
	\( -name 'extlinux.conf' -o -name 'uEnv.txt' -o -name 'armbianEnv.txt' \
	-o -name 'config.txt' -o -name '*overlay*' \) \
	-print 2>/dev/null ||
	true

echo "=== DRM CONNECTORS (cached sysfs only) ==="
for con in /sys/class/drm/card*-*; do
	[ -d "$con" ] || continue
	echo "-- $con"
	[ -r "$con/status" ] && printf 'status=' && cat "$con/status"
	[ -r "$con/enabled" ] && printf 'enabled=' && cat "$con/enabled"
	[ -r "$con/modes" ] && sed -n '1,12p' "$con/modes"
done

echo "=== BACKLIGHT DEVICES ==="
for dev in /sys/class/backlight/*; do
	[ -d "$dev" ] || continue
	echo "-- $dev"
	for attr in brightness actual_brightness max_brightness bl_power type; do
		[ -r "$dev/$attr" ] && printf '%s=' "$attr" && cat "$dev/$attr"
	done
done

echo "=== CURRENT DRM ATOMIC STATE ==="
for state in /sys/kernel/debug/dri/0/state /sys/kernel/debug/dri/1/state; do
	[ -r "$state" ] || continue
	echo "-- $state"
	cat "$state"
done

echo "=== DISPLAY/IOMMU FAULT COUNTS ==="
log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT HUP INT TERM
journalctl -b 0 -k --no-pager -q -o short-monotonic >"$log_file"
for pattern in \
	'sunxi_de_atomic_flush timeout' \
	'PageTable Invalid' \
	'Bug is in DE' \
	'SUNXI DRM DEBUG' \
	'sunxi_iommu_irq'; do
	printf '%s=' "$pattern"
	grep -E -i -c "$pattern" "$log_file" || true
done

echo "=== RELEVANT KERNEL TIMELINE ==="
grep -E -i \
	'Linux version|AW BSP version|sunxi.*drm|display.engine|tcon|dsi|panel|hdmi|iommu|atomic_flush|PageTable Invalid|Bug is in DE' \
	"$log_file" |
	tail -n 300 ||
	true

echo "=== PSTORE ==="
if [ -d /sys/fs/pstore ]; then
	find /sys/fs/pstore -maxdepth 1 -type f -print
else
	echo "no pstore mount"
fi
