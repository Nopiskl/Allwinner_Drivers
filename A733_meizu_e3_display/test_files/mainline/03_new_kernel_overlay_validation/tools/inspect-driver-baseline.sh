set -u

echo '=== identity ==='
uname -a
printf 'BOOT_ID='; cat /proc/sys/kernel/random/boot_id
echo '=== installed packages ==='
dpkg-query -W -f='${binary:Package}\t${Version}\n' \
  dkms linux-headers-$(uname -r) radxa-touchscreen-utils 2>&1 || true
echo '=== DKMS/modules ==='
dkms status 2>&1 || true
find /lib/modules/$(uname -r) -type f \( -name 'sec_ts.ko*' -o -name 'sgm37604a.ko*' \) -print
lsmod | grep -E '(^| )(sec_ts|sgm37604a)( |$)' || true
echo '=== I2C binding ==='
for dev in 0-0036 0-0048; do
  printf '%s compatible=' "$dev"
  tr '\0' ' ' < "/sys/bus/i2c/devices/$dev/of_node/compatible" 2>/dev/null || true
  printf ' driver='
  readlink "/sys/bus/i2c/devices/$dev/driver" 2>/dev/null || echo unbound
done
echo '=== current input ==='
grep -EH '^(N: Name|H: Handlers|B: PROP)' /proc/bus/input/devices || true
echo '=== mapping package files ==='
dpkg -L radxa-touchscreen-utils 2>&1 || true
echo '=== mapping executable ==='
file /usr/bin/radxa-map-tp 2>&1 || true
sed -n '1,240p' /usr/bin/radxa-map-tp 2>&1 || true
echo '=== mapping configs ==='
for f in \
  /etc/xdg/autostart/radxa-map-tp.desktop \
  /usr/share/sddm/sddm.conf.d/radxa-map-tp_sddm.conf \
  /usr/lib/sddm/sddm.conf.d/radxa-map-tp_sddm.conf \
  /usr/share/sddm/scripts/Xsetup; do
  if test -e "$f"; then
    echo "--- $f"
    sed -n '1,240p' "$f"
  fi
done
echo '=== mapping references ==='
grep -Rsn --exclude='*.pyc' 'radxa-map-tp' \
  /etc/xdg /usr/share/sddm /usr/lib/sddm /usr/share/applications \
  2>/dev/null || true
echo '=== X/SDDM ==='
ps -eo user,pid,args | grep -E '[X]org|[s]ddm' || true
echo '=== backlight ==='
for b in /sys/class/backlight/*; do
  test -d "$b" || continue
  echo "--- $b"
  for a in type brightness actual_brightness max_brightness bl_power; do
    test -r "$b/$a" && printf '%s=' "$a" && cat "$b/$a"
  done
done
echo '=== recent relevant kernel log ==='
journalctl -k -b --no-pager | grep -Ei \
  'sec_ts|sgm37604|backlight|i2c-gpio|dsi|drm|rcu.*stall|watchdog|Oops|panic|NULL pointer' \
  | tail -n 240 || true
