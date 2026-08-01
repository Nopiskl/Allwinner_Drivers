#!/bin/sh
set -eu

echo "=== current boot ==="
uname -a
cat /proc/uptime
cat /proc/sys/kernel/random/boot_id

echo "=== touch mapper process (no xrandr) ==="
pgrep -af '/usr/lib/meizu-e3-dkms/map-touch-to-dsi.sh' || true

echo "=== installed kernel packages ==="
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
	'linux-image-*a733' 'linux-headers-*a733' 2>/dev/null || true

echo "=== previous boot identity ==="
journalctl -b -1 -k --no-pager -o short-monotonic |
	sed -n '1,20p'

echo "=== previous boot display fault timeline ==="
journalctl -b -1 -k --no-pager -o short-monotonic |
	grep -E -i \
		'sunxi_de_atomic_flush|PageTable Invalid|Bug is in DE|sunxi_iommu_irq|exception record|SUNXI DRM DEBUG|DE-[01] exception|map:|drm hdmi|hpd|hotplug|atomic_(disable|enable)|sunxi_de_(disable|enable)' ||
	true

echo "=== previous boot tail ==="
journalctl -b -1 -k --no-pager -o short-monotonic | tail -n 250

echo "=== current boot early display messages ==="
journalctl -b 0 -k --no-pager -o short-monotonic |
	grep -E -i \
		'Linux version|AW BSP version|sunxi.*drm|display.engine|tcon|dsi|panel|hdmi|iommu|sgm37604|sec_ts' ||
	true
