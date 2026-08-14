#!/bin/sh

set -eu

is_loaded()
{
	grep -q "^$1 " /proc/modules
}

unload_one()
{
	NAME=$1
	if is_loaded "$NAME"; then
		echo "unloading $NAME"
		rmmod "$NAME"
	else
		echo "$NAME is not loaded"
	fi
}

if pidof lv_examples >/dev/null 2>&1; then
	echo 'ERROR: lv_examples is still running; stop it before unloading lcd_fb.' >&2
	exit 1
fi

unload_one lcd_fb
unload_one lcd_fb_spi_panel
unload_one fb_sys_fops

echo 'LCD modules unloaded.'
