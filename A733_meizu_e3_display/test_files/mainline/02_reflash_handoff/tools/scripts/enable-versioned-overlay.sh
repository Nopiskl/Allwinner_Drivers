#!/bin/sh
#
# Enable one already-staged, versioned DTBO while preserving l0r as rescue.
# Run only after the new image has been verified to use u-boot-update/extlinux
# with labels l0 and l0r.
#
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run as root.\n' >&2
    exit 1
fi
if [ "$#" -ne 1 ]; then
    printf 'Usage: %s /boot/dtbo/<versioned-name>.dtbo.disabled\n' "$0" >&2
    exit 2
fi

DISABLED="$1"
case "$DISABLED" in
    /boot/dtbo/*.dtbo.disabled)
        ;;
    *)
        printf 'Refusing path outside /boot/dtbo or without .dtbo.disabled: %s\n' \
            "$DISABLED" >&2
        exit 2
        ;;
esac

ACTIVE="${DISABLED%.disabled}"
EXTLINUX=/boot/extlinux/extlinux.conf
BACKUP_DIR=/boot/extlinux/backups
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_DIR/extlinux.conf.pre-enable-$STAMP"

test -f "$DISABLED"
test ! -e "$ACTIVE"
test -x /usr/sbin/u-boot-update
test -f "$EXTLINUX"
grep -q '^label l0$' "$EXTLINUX"
grep -q '^label l0r$' "$EXTLINUX"
awk '
    /^label l0r$/ { in_rescue=1; next }
    /^label / { in_rescue=0 }
    in_rescue && /(^|[[:space:]])single([[:space:]]|$)/ { found=1 }
    END { exit(found ? 0 : 1) }
' "$EXTLINUX"

mkdir -p "$BACKUP_DIR"
cp -a -- "$EXTLINUX" "$BACKUP"
mv -- "$DISABLED" "$ACTIVE"

rollback() {
    if [ -f "$ACTIVE" ] && [ ! -e "$DISABLED" ]; then
        mv -- "$ACTIVE" "$DISABLED"
    fi
    /usr/sbin/u-boot-update || true
}
trap rollback HUP INT TERM

if ! /usr/sbin/u-boot-update; then
    rollback
    trap - HUP INT TERM
    printf 'u-boot-update failed; overlay returned to disabled state.\n' >&2
    exit 1
fi

OVERLAY_BASENAME="$(basename "$ACTIVE")"
if ! awk -v expected="$ACTIVE" '
    /^label l0$/ { in_normal=1; next }
    /^label / { in_normal=0 }
    in_normal && $1 == "fdtoverlays" {
        for (i=2; i<=NF; i++) if ($i == expected) found=1
    }
    END { exit(found ? 0 : 1) }
' "$EXTLINUX"; then
    rollback
    trap - HUP INT TERM
    printf 'Normal entry does not reference %s; rolled back.\n' \
        "$OVERLAY_BASENAME" >&2
    exit 1
fi

if awk '
    /^label l0r$/ { in_rescue=1; next }
    /^label / { in_rescue=0 }
    in_rescue && $1 == "fdtoverlays" { found=1 }
    END { exit(found ? 0 : 1) }
' "$EXTLINUX"; then
    rollback
    trap - HUP INT TERM
    printf 'Rescue entry unexpectedly contains fdtoverlays; rolled back.\n' >&2
    exit 1
fi

sync
trap - HUP INT TERM
printf 'ENABLED=%s\n' "$ACTIVE"
printf 'BACKUP=%s\n' "$BACKUP"
sha256sum "$ACTIVE"
awk '/^default |^label |^[[:space:]]*fdtoverlays|^[[:space:]]*append / {
    print NR ":" $0
}' "$EXTLINUX"
