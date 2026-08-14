#!/bin/sh

set -eu

BUNDLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BACKUP_DIR="$BUNDLE_DIR/backup"
STAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP="$BACKUP_DIR/boot_mtd4_${STAMP}.img"

grep -q '^mtd4: 00500000 00010000 "boot"$' /proc/mtd || {
	echo 'ERROR: mtd4 is not the expected 5 MiB boot partition.' >&2
	exit 1
}

mkdir -p "$BACKUP_DIR"
dd if=/dev/mtd4 of="$BACKUP" bs=65536 count=80
sync

SIZE=$(wc -c < "$BACKUP" | tr -d ' ')
[ "$SIZE" = '5242880' ] || {
	echo "ERROR: backup size is $SIZE, expected 5242880." >&2
	exit 1
}

(
	cd "$BACKUP_DIR"
	sha256sum "$(basename "$BACKUP")" | tee "$(basename "$BACKUP").sha256"
)
echo "Boot backup complete: $BACKUP"
echo 'This script only read NOR; the backup was written to the SD card.'
