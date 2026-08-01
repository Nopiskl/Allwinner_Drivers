#!/bin/sh
#
# Disable one exact versioned overlay from the overlay-free l0r rescue entry.
# The DTBO is renamed, never deleted.
#
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run as root.\n' >&2
    exit 1
fi
if [ "$#" -ne 1 ]; then
    printf 'Usage: %s /boot/dtbo/<versioned-name>.dtbo\n' "$0" >&2
    exit 2
fi

ACTIVE="$1"
case "$ACTIVE" in
    /boot/dtbo/*.dtbo)
        ;;
    *)
        printf 'Refusing path outside /boot/dtbo or without .dtbo: %s\n' \
            "$ACTIVE" >&2
        exit 2
        ;;
esac

case " $(cat /proc/cmdline) " in
    *" single "*)
        ;;
    *)
        printf 'Refusing rollback outside a boot with the single parameter.\n' >&2
        exit 1
        ;;
esac

DISABLED="$ACTIVE.disabled"
EXTLINUX=/boot/extlinux/extlinux.conf
BACKUP_DIR=/boot/extlinux/backups
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_DIR/extlinux.conf.pre-rollback-$STAMP"

test -f "$ACTIVE"
test ! -e "$DISABLED"
test -x /usr/sbin/u-boot-update
test -f "$EXTLINUX"

mkdir -p "$BACKUP_DIR"
cp -a -- "$EXTLINUX" "$BACKUP"
mv -- "$ACTIVE" "$DISABLED"

if ! /usr/sbin/u-boot-update; then
    mv -- "$DISABLED" "$ACTIVE"
    /usr/sbin/u-boot-update || true
    printf 'u-boot-update failed; original active state restored.\n' >&2
    exit 1
fi

if grep -Fq "$ACTIVE" "$EXTLINUX"; then
    mv -- "$DISABLED" "$ACTIVE"
    /usr/sbin/u-boot-update || true
    printf 'Generated extlinux still references the disabled overlay; restored.\n' \
        >&2
    exit 1
fi

if awk '
    /^label l0r$/ { in_rescue=1; next }
    /^label / { in_rescue=0 }
    in_rescue && $1 == "fdtoverlays" { found=1 }
    END { exit(found ? 0 : 1) }
' "$EXTLINUX"; then
    mv -- "$DISABLED" "$ACTIVE"
    /usr/sbin/u-boot-update || true
    printf 'Rescue entry contains fdtoverlays; original state restored.\n' >&2
    exit 1
fi

sync
printf 'DISABLED=%s\n' "$DISABLED"
printf 'BACKUP=%s\n' "$BACKUP"
sha256sum "$DISABLED"
awk '/^default |^label |^[[:space:]]*fdtoverlays|^[[:space:]]*append / {
    print NR ":" $0
}' "$EXTLINUX"
