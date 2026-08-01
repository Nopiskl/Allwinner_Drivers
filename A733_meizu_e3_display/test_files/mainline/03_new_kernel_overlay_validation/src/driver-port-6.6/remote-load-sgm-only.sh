set -euxo pipefail

test "$(cat /proc/sys/kernel/random/boot_id)" = \
  7a8fe62e-d15a-4392-ad59-a74c783e215a
test ! -e /sys/bus/i2c/devices/0-0036/driver
test ! -e /sys/module/sgm37604a
test ! -e /sys/module/sec_ts

marker="meizu-e3-load-sgm-$(date +%s)"
logger -p kern.notice "$marker begin"
/sbin/modprobe sgm37604a
sleep 3
logger -p kern.notice "$marker end"

echo '=== binding/module ==='
readlink /sys/bus/i2c/devices/0-0036/driver
test -e /sys/module/sgm37604a
test ! -e /sys/module/sec_ts
lsmod | grep -E '^(sgm37604a|sec_ts)\b' || true

echo '=== backlight classes ==='
for b in /sys/class/backlight/*; do
  test -d "$b" || continue
  echo "--- $b"
  readlink -f "$b/device"
  for a in type brightness actual_brightness max_brightness bl_power; do
    test -r "$b/$a" && printf '%s=' "$a" && cat "$b/$a"
  done
done

echo '=== SGM kernel messages ==='
dmesg --color=never | grep -E \
  "$marker|SGM37604A|sgm37604a|rcu.*stall|watchdog|Oops|panic|NULL pointer" \
  | tail -n 160
