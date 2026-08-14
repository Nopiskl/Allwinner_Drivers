#!/bin/sh

set -eu

BUNDLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPI1_NODE=/proc/device-tree/soc@2002000/spi@44026000
LCDFB_NODE=/proc/device-tree/soc@2002000/lcd_fb

read_dt_string()
{
	if [ -r "$1" ]; then
		tr -d '\000' < "$1"
	else
		printf '%s' '<missing>'
	fi
}

printf 'kernel: %s\n' "$(uname -r)"
printf 'machine: %s\n' "$(uname -m)"
printf '%s\n' 'mtd:'
cat /proc/mtd

grep -q '^mtd4: 00500000 00010000 "boot"$' /proc/mtd || {
	echo 'ERROR: mtd4 is not the expected 5 MiB boot partition.' >&2
	exit 1
}

[ "$(uname -r)" = '5.4.220' ] || {
	echo 'ERROR: kernel release does not match module vermagic.' >&2
	exit 1
}

printf 'spi1 status: %s\n' "$(read_dt_string "$SPI1_NODE/status")"
printf 'lcd_fb status: %s\n' "$(read_dt_string "$LCDFB_NODE/status")"

if [ -r "$SPI1_NODE/slave@0/lcd_model_name" ]; then
	printf 'panel: %s\n' "$(read_dt_string "$SPI1_NODE/slave@0/lcd_model_name")"
	printf 'panel driver: %s\n' "$(read_dt_string "$SPI1_NODE/slave@0/lcd_driver_name")"
else
	echo 'panel: <missing; expected before first boot update>'
fi

if command -v sha256sum >/dev/null 2>&1; then
	(
		cd "$BUNDLE_DIR"
		sha256sum -c SHA256SUMS
	)
else
	echo 'WARNING: sha256sum is unavailable; package integrity was not checked.' >&2
fi

echo 'Preflight complete. This script did not write NOR or load modules.'
