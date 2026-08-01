set -euxo pipefail

test "$(cat /proc/sys/kernel/random/boot_id)" = \
  7a8fe62e-d15a-4392-ad59-a74c783e215a
test -e /sys/module/sgm37604a
test -e /sys/bus/i2c/devices/0-0036/driver
test ! -e /sys/module/sec_ts
test ! -e /sys/bus/i2c/devices/0-0048/driver

before=$(dmesg --color=never | wc -l)
/sbin/modprobe sec_ts
sleep 12

echo '=== binding/module ==='
readlink /sys/bus/i2c/devices/0-0048/driver
test -e /sys/module/sec_ts
lsmod | grep -E '^(sgm37604a|sec_ts)\b'

echo '=== Samsung input ==='
grep -n -A8 -B2 'Samsung Electronics Touchscreen 1223' \
  /proc/bus/input/devices
for input in /sys/class/input/input*; do
  test -r "$input/name" || continue
  if grep -qx 'Samsung Electronics Touchscreen 1223' "$input/name"; then
    echo "INPUT_SYSFS=$input"
    readlink -f "$input/device"
  fi
done

echo '=== new kernel messages ==='
dmesg --color=never | tail -n "+$((before + 1))"

echo '=== fatal-pattern check, entire boot ==='
dmesg --color=never | grep -Ei \
  'rcu.*stall|watchdog.*lockup|soft lockup|hard LOCKUP|Oops|panic|NULL pointer|atomic commit.*timed out|iommu.*fault' \
  | tail -n 120 || true
