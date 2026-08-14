#!/bin/sh
# Recover RTL8201F from the incorrectly strapped 100Base-FX mode.
# Usage: ./gmac_recover.sh [interface]

set -u

IFACE=${1:-eth0}
MDIO_DIR=${MDIO_DIR:-/sys/bus/platform/devices/44500048.mdio}
PHY_ADDR=${PHY_ADDR:-0}
MII_READ="$MDIO_DIR/mii_read"
MII_WRITE="$MDIO_DIR/mii_write"

fail()
{
	echo "gmac_recover: $*" >&2
	exit 1
}

mdio_write()
{
	printf '%s %s %s\n' "$PHY_ADDR" "$1" "$2" > "$MII_WRITE" ||
		fail "cannot prepare PHY register write"

	# This sunxi driver performs the saved write in mii_write's show callback.
	cat "$MII_WRITE" || fail "cannot write PHY register $1"
}

mdio_read()
{
	printf '%s %s\n' "$PHY_ADDR" "$1" > "$MII_READ" ||
		fail "cannot select PHY register $1"
	cat "$MII_READ" || fail "cannot read PHY register $1"
}

reg_value()
{
	value=${1##*0x}
	case "$value" in
		''|*[!0-9a-fA-F]*) fail "unexpected MDIO output: $1" ;;
	esac
	printf '%s\n' "$value"
}

[ -w "$MII_READ" ] && [ -w "$MII_WRITE" ] ||
	fail "MDIO sysfs files not found under $MDIO_DIR"
[ -d "/sys/class/net/$IFACE" ] || fail "network interface $IFACE not found"

if command -v ifconfig >/dev/null 2>&1; then
	ifconfig "$IFACE" up || fail "cannot bring $IFACE up"
elif command -v ip >/dev/null 2>&1; then
	ip link set dev "$IFACE" up || fail "cannot bring $IFACE up"
else
	fail "neither ifconfig nor ip is available"
fi

echo "gmac_recover: select RTL8201F page 0"
mdio_write 1f 0000

id1_line=$(mdio_read 02) || fail "cannot read PHY ID1"
id2_line=$(mdio_read 03) || fail "cannot read PHY ID2"
id1_hex=$(reg_value "$id1_line") || exit 1
id2_hex=$(reg_value "$id2_line") || exit 1
[ "$id1_hex:$id2_hex" = "001c:c816" ] ||
	fail "unexpected PHY ID 0x$id1_hex:0x$id2_hex"

before_line=$(mdio_read 1c) || fail "cannot read Reg28"
before_hex=$(reg_value "$before_line") || exit 1
before=$((0x$before_hex))
after=$((before & 0xffdf))
after_hex=$(printf '%04x' "$after")

printf 'gmac_recover: Reg28 0x%s -> 0x%s (clear FXMODE bit 5)\n' \
	"$before_hex" "$after_hex"
mdio_write 1c "$after_hex"

# Advertise 10/100 half/full duplex plus pause capabilities, then restart AN.
mdio_write 04 0de1
mdio_write 00 1200

check_line=$(mdio_read 1c) || fail "cannot verify Reg28"
check_hex=$(reg_value "$check_line") || exit 1
check=$((0x$check_hex))
[ $((check & 0x20)) -eq 0 ] || fail "FXMODE is still set (Reg28=0x$check_hex)"

sleep 1
second=1
while [ "$second" -le 12 ]; do
	carrier=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0)
	if [ "$carrier" = "1" ]; then
		speed=$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null || echo unknown)
		duplex=$(cat "/sys/class/net/$IFACE/duplex" 2>/dev/null || echo unknown)
		echo "gmac_recover: link up, ${speed}Mbps/${duplex}, Reg28=0x$check_hex"
		exit 0
	fi
	echo "gmac_recover: waiting for link (${second}/12)"
	sleep 1
	second=$((second + 1))
done

echo "gmac_recover: link did not come up" >&2
mdio_read 00 >&2
mdio_read 01 >&2
mdio_read 04 >&2
mdio_read 05 >&2
mdio_read 1c >&2
exit 1
