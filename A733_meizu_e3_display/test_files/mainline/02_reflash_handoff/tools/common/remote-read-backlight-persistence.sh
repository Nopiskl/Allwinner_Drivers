#!/bin/sh
set -eu

echo "=== systemd saved backlight files ==="
if [ -d /var/lib/systemd/backlight ]; then
	for file in /var/lib/systemd/backlight/*; do
		[ -f "$file" ] || continue
		echo "-- $file"
		cat "$file"
	done
fi

echo "=== relevant user power settings ==="
find /home/radxa/.config -maxdepth 2 -type f \
	\( -iname '*power*' -o -iname '*screen*' \) -print 2>/dev/null |
	while IFS= read -r file; do
		echo "-- $file"
		grep -E -i 'brightness|dim|backlight' "$file" || true
	done
