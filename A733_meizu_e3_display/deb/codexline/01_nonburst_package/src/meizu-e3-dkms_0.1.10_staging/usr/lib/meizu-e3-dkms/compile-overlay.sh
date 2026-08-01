#!/bin/sh
# Build overlay on the install machine (needs linux-headers matching uname -r, and dtc).
# cpp must see arch DTS + dt-bindings includes so GPIO_*/MIPI_* macros expand before dtc.
set -e

OVERLAY=/usr/src/meizu-e3-dkms-0.1.10/overlay/cubie-a7a-meizu-e3-display.dtso
OUTPUT=cubie-a7a-meizu-e3-display-v002.dtbo
[ -f "$OVERLAY" ] || exit 0

if ! command -v cpp >/dev/null 2>&1 || ! command -v dtc >/dev/null 2>&1; then
	echo "meizu-e3-dkms: need cpp and dtc (e.g. apt install build-essential device-tree-compiler)" >&2
	exit 0
fi

KVER=$(uname -r)
KDIR=
for d in "/lib/modules/$KVER/build" "/usr/src/linux-headers-$KVER"; do
	[ -d "$d" ] && KDIR=$d && break
done
if [ -z "$KDIR" ]; then
	echo "meizu-e3-dkms: no kernel build tree for $KVER; install linux-headers-$KVER from your vendor" >&2
	exit 0
fi

case $(uname -m) in
aarch64) ARCH=arm64 ;;
armv7l|armv6l|armv5*) ARCH=arm ;;
*) ARCH=arm64 ;;
esac

# -D__DTS__ and same -I layout the kernel uses for out-of-tree DTS preprocessing
CPP_BASE="-nostdinc -undef -D__DTS__ -x assembler-with-cpp -E"
CPP_INC="-I$KDIR/include"
[ -d "$KDIR/arch/$ARCH/boot/dts/include" ] && CPP_INC="$CPP_INC -I$KDIR/arch/$ARCH/boot/dts/include"
[ -d "$KDIR/arch/$ARCH/boot/dts" ] && CPP_INC="$CPP_INC -I$KDIR/arch/$ARCH/boot/dts"
[ -d "$KDIR/scripts/dtc/include-prefixes" ] && CPP_INC="$CPP_INC -I$KDIR/scripts/dtc/include-prefixes"

TMP=$(mktemp)
DTBO=$(mktemp)
trap 'rm -f "$TMP" "$DTBO"' EXIT

cpp $CPP_BASE $CPP_INC "$OVERLAY" "$TMP"
dtc -@ -I dts -O dtb -o "$DTBO" "$TMP" > /dev/null 2>&1

if [ -f "/boot/dtbo/$OUTPUT" ]; then
    install -m 0644 "$DTBO" "/boot/dtbo/$OUTPUT"
else
    install -m 0644 "$DTBO" "/boot/dtbo/$OUTPUT.disabled"
    echo "**************************************************
****You may enable overlay by running rsetup****
**************************************************"
fi
