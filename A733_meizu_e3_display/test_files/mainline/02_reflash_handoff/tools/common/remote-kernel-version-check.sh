#!/bin/sh
set -eu

echo "=== current kernel/BSP ==="
uname -a
journalctl -b 0 -k --no-pager -q |
	grep -E -i 'Linux version|AW BSP version' |
	head -n 20 ||
	true

echo "=== A733 package candidates (cached repository metadata only) ==="
apt-cache policy \
	linux-image-radxa-a733 \
	linux-headers-radxa-a733 \
	linux-image-5.15.147-21-a733 \
	linux-headers-5.15.147-21-a733 2>/dev/null ||
	true

echo "=== installed package versions ==="
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
	'linux-image-*a733' 'linux-headers-*a733' 2>/dev/null ||
	true

echo "=== installed source RCQ force-update references ==="
for root in \
	/usr/src/linux-headers-5.15.147-14-a733 \
	/usr/src/linux-headers-5.15.147-14-a733-common; do
	[ -d "$root" ] || continue
	grep -R -n -m 12 \
		'de_top_update_force_by_ahb' \
		"$root" 2>/dev/null ||
		true
done
