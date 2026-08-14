#!/bin/sh

set -eu

BUNDLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODULE_DIR="$BUNDLE_DIR/modules"
SPI1_STATUS=/proc/device-tree/soc@2002000/spi@44026000/status
LCDFB_STATUS=/proc/device-tree/soc@2002000/lcd_fb/status
EXPECTED_LCD_FB_SHA256=d487d338a2210e9226ff7651f333d70e49b3159418fcbc6d2e27f1e0a4df25e2
EXPECTED_LCD_FB_SRCVERSION=67770EC052084657BDF7FE4

is_loaded()
{
	grep -q "^$1 " /proc/modules
}

load_one()
{
	NAME=$1
	FILE=$2
	if is_loaded "$NAME"; then
		echo "$NAME already loaded"
	else
		echo "loading $NAME"
		insmod "$FILE"
	fi
}

[ "$(uname -r)" = '5.4.220' ] || {
	echo 'ERROR: expected kernel 5.4.220.' >&2
	exit 1
}

[ "$(tr -d '\000' < "$SPI1_STATUS" 2>/dev/null || true)" = 'okay' ] || {
	echo 'ERROR: SPI1 is not okay in the running DT; boot update has not taken effect.' >&2
	exit 1
}

[ "$(tr -d '\000' < "$LCDFB_STATUS" 2>/dev/null || true)" = 'okay' ] || {
	echo 'ERROR: lcd_fb is not okay in the running DT; boot update has not taken effect.' >&2
	exit 1
}

ACTUAL_LCD_FB_SHA256=$(sha256sum "$MODULE_DIR/lcd_fb.ko" | awk '{print $1}')
[ "$ACTUAL_LCD_FB_SHA256" = "$EXPECTED_LCD_FB_SHA256" ] || {
	echo "ERROR: formal lcd_fb.ko SHA-256 mismatch: $ACTUAL_LCD_FB_SHA256" >&2
	exit 1
}

if is_loaded lcd_fb; then
	LOADED_SRCVERSION=$(cat /sys/module/lcd_fb/srcversion 2>/dev/null || true)
	LOADED_SPI_SPEED=$(cat /sys/module/lcd_fb/parameters/spi_speed_hz 2>/dev/null || true)
	if [ "$LOADED_SRCVERSION" != "$EXPECTED_LCD_FB_SRCVERSION" ] ||
	   [ "$LOADED_SPI_SPEED" != '0' ]; then
		PIDS=$(pidof lv_examples 2>/dev/null || true)
		if [ -n "$PIDS" ]; then
			echo "stopping lv_examples: $PIDS"
			kill $PIDS
			sleep 1
		fi
		echo "replacing lcd_fb srcversion=$LOADED_SRCVERSION spi_speed_hz=$LOADED_SPI_SPEED"
		rmmod lcd_fb
	fi
fi

load_one fb_sys_fops "$MODULE_DIR/fb_sys_fops.ko"
load_one lcd_fb_spi_panel "$MODULE_DIR/lcd_fb_spi_panel.ko"
load_one lcd_fb "$MODULE_DIR/lcd_fb.ko"

sleep 1

LCD_FB_SYS=
for FB_SYS in /sys/class/graphics/fb*; do
	[ -e "$FB_SYS" ] || continue
	case "$(readlink "$FB_SYS" 2>/dev/null || true)" in
		*lcd_fb*)
			LCD_FB_SYS=$FB_SYS
			break
			;;
	esac
done

if [ -z "$LCD_FB_SYS" ]; then
	echo 'ERROR: no framebuffer owned by lcd_fb was created. Recent dmesg follows:' >&2
	dmesg | tail -n 100 >&2
	exit 1
fi

LCD_FB_DEVICE=/dev/${LCD_FB_SYS##*/}
echo 'Framebuffer created:'
ls -l "$LCD_FB_DEVICE"
for PROP in name virtual_size bits_per_pixel; do
	if [ -r "$LCD_FB_SYS/$PROP" ]; then
		printf '%s: ' "$PROP"
		cat "$LCD_FB_SYS/$PROP"
	fi
done

if [ "$(cat "$LCD_FB_SYS/virtual_size")" != '240,560' ] ||
   [ "$(cat "$LCD_FB_SYS/bits_per_pixel")" != '16' ]; then
	echo 'ERROR: lcd_fb is not 240x280 RGB565 with two buffers.' >&2
	exit 1
fi

[ "$(cat /sys/module/lcd_fb/srcversion)" = "$EXPECTED_LCD_FB_SRCVERSION" ] || {
	echo 'ERROR: unexpected loaded lcd_fb srcversion.' >&2
	exit 1
}

[ "$(cat /sys/module/lcd_fb/parameters/spi_speed_hz)" = '0' ] || {
	echo 'ERROR: formal lcd_fb must use spi_speed_hz=0 (DTS 48 MHz).' >&2
	exit 1
}

echo "lcd_fb device: $LCD_FB_DEVICE"
echo "lcd_fb formal release srcversion: $EXPECTED_LCD_FB_SRCVERSION"
echo 'lcd_fb formal release spi_speed_hz: 0 (DTS 48000000)'
echo 'LCD formal release modules loaded successfully.'
