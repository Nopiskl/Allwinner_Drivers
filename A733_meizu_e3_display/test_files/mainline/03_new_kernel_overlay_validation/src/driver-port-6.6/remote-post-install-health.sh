set -u

echo '=== start ==='
date --iso-8601=seconds
uptime
printf 'BOOT_ID='; cat /proc/sys/kernel/random/boot_id
echo '=== touchscreen monitor ==='
ps -eo user,pid,args | grep -E '[r]adxa-(tp-mon|map-tp)' || true
file /usr/bin/radxa-tp-mon
sed -n '1,260p' /usr/bin/radxa-tp-mon
echo '=== wait 30 seconds ==='
sleep 30
echo '=== health ==='
date --iso-8601=seconds
uptime
readlink /sys/bus/i2c/devices/0-0036/driver
readlink /sys/bus/i2c/devices/0-0048/driver
lsmod | grep -E '^(sgm37604a|sec_ts)\b'
echo '=== IRQ ==='
grep -Ei 'sec_ts|gpio.*107|gpio.*114|i2c.*gpio' /proc/interrupts || true
echo '=== backlight ==='
for b in /sys/class/backlight/*; do
  test -d "$b" || continue
  printf '%s ' "$(basename "$b")"
  for a in brightness actual_brightness max_brightness bl_power; do
    test -r "$b/$a" && printf '%s=%s ' "$a" "$(cat "$b/$a")"
  done
  echo
done
echo '=== fatal-pattern check ==='
dmesg --color=never | grep -Ei \
  'rcu.*stall|watchdog.*lockup|soft lockup|hard LOCKUP|Oops|panic|NULL pointer|atomic commit.*timed out|iommu.*fault' \
  | tail -n 120 || true
echo '=== latest SEC/SGM messages ==='
dmesg --color=never | grep -Ei 'sec_ts|sgm37604a|Samsung Electronics Touchscreen' \
  | tail -n 200
