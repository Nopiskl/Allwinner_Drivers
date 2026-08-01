set -euxo pipefail

test -e /sys/module/sec_ts
test -e /sys/module/sgm37604a

install -m 0644 /tmp/meizu-e3-drivers.conf \
  /etc/modules-load.d/meizu-e3-drivers.conf
install -m 0644 /tmp/meizu-e3-sec-ts-quarantine.conf \
  /etc/modprobe.d/meizu-e3-sec-ts-quarantine.conf

irq_before=$(awk '$NF == "sec_ts" {print $2; exit}' /proc/interrupts)
/sbin/modprobe -r sec_ts
sleep 3

echo "SEC_IRQ_COUNT_BEFORE_UNLOAD=$irq_before"
test ! -e /sys/module/sec_ts
test ! -e /sys/bus/i2c/devices/0-0048/driver
test -e /sys/module/sgm37604a
test -e /sys/bus/i2c/devices/0-0036/driver
! grep -q 'Samsung Electronics Touchscreen 1223' /proc/bus/input/devices

echo '=== safe persistent state ==='
cat /etc/modules-load.d/meizu-e3-drivers.conf
cat /etc/modprobe.d/meizu-e3-sec-ts-quarantine.conf
/usr/sbin/dkms status -m meizu-e3-drivers-t4 -v 0.1.10
lsmod | grep -E '^(sgm37604a|sec_ts)\b' || true
ps -eLo pid,tid,psr,pcpu,stat,comm,wchan:28 --sort=-pcpu | head -n 18
echo '=== backlight remains bound ==='
readlink /sys/bus/i2c/devices/0-0036/driver
for a in brightness actual_brightness max_brightness bl_power; do
  printf '%s=' "$a"; cat "/sys/class/backlight/sgm37604a/$a"
done
echo '=== boot configuration still unchanged ==='
sha256sum -c \
  /var/lib/meizu-e3-drivers-t4/20260731-t4-v001-reg1/preinstall/boot-sha256.txt
