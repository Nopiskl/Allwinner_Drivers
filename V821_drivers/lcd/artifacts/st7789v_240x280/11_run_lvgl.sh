#!/bin/sh

set -eu

BUNDLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LVGL_BIN="$BUNDLE_DIR/userspace/lv_examples"
DEMO=${1:-1}
LCD_FB_DEVICE=

for FB_SYS in /sys/class/graphics/fb*; do
	[ -e "$FB_SYS" ] || continue
	case "$(readlink "$FB_SYS" 2>/dev/null || true)" in
		*lcd_fb*)
			LCD_FB_DEVICE=/dev/${FB_SYS##*/}
			break
			;;
	esac
done

[ -n "$LCD_FB_DEVICE" ] && [ -e "$LCD_FB_DEVICE" ] || {
	echo 'ERROR: no framebuffer owned by lcd_fb was found; load lcd_fb first.' >&2
	exit 1
}

chmod 0755 "$LVGL_BIN"
export LV_SUNXIFB_DEVICE="$LCD_FB_DEVICE"
echo "Starting LVGL demo $DEMO on $LCD_FB_DEVICE in the foreground."
echo 'Touch input is intentionally not adapted.'
exec "$LVGL_BIN" "$DEMO"
