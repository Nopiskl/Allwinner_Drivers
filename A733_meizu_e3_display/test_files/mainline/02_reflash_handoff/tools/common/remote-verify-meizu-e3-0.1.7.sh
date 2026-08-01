#!/bin/sh
set -eu

sudo -S -p "" -v

printf "%s\n" "Kernel log:"
sudo journalctl -k -b --no-pager |
	grep -E -i "sgm37604a|sec_ts|backlight|touchscreen" |
	tail -n 100 || true

printf "%s\n" "SGM37604A registers on i2c-0:"
for reg in 0x10 0x11 0x19 0x1a 0x1b 0x1f; do
	value=$(sudo i2cget -y -f 0 0x36 "$reg" b)
	printf "%s=%s\n" "$reg" "$value"
done

printf "%s\n" "Touch mapping test on the current SDDM X11 display:"
xauth=$(sudo -S find /var/run/sddm -maxdepth 1 -type f | head -n 1)
if [ -n "$xauth" ]; then
	sudo -S runuser -u sddm -- env DISPLAY=:0 XAUTHORITY="$xauth" xrandr --query |
		grep -E "^(DSI-1|HDMI-1) "
	printf "%s\n" "Before:"
	sudo -S runuser -u sddm -- env DISPLAY=:0 XAUTHORITY="$xauth" \
		xinput list-props "Samsung Electronics Touchscreen 1223" |
		grep "Coordinate Transformation Matrix"
	sudo -S runuser -u sddm -- env DISPLAY=:0 XAUTHORITY="$xauth" XDG_SESSION_TYPE=x11 \
		timeout 4 /usr/lib/meizu-e3-dkms/map-touch-to-dsi.sh || true
	printf "%s\n" "After:"
	sudo -S runuser -u sddm -- env DISPLAY=:0 XAUTHORITY="$xauth" \
		xinput list-props "Samsung Electronics Touchscreen 1223" |
		grep "Coordinate Transformation Matrix"
fi
