set -euxo pipefail

test -e /sys/module/sec_ts
test -e /sys/bus/i2c/devices/0-0048/driver

display=:0
auth=$(ps -eo args | awk '
  /\/usr\/bin\/X / {
    for (i = 1; i <= NF; i++)
      if ($i == "-auth") { print $(i + 1); exit }
  }')
test -n "$auth"
test -r "$auth"
export DISPLAY="$display" XAUTHORITY="$auth"

echo "DISPLAY=$DISPLAY"
echo "XAUTHORITY=$XAUTHORITY"
echo '=== xrandr layout ==='
xrandr --query | grep -E '^(DSI|HDMI).* connected|^Screen '
echo '=== touch before ==='
device_id=$(xinput list --id-only 'Samsung Electronics Touchscreen 1223' | head -n 1)
test -n "$device_id"
echo "DEVICE_ID=$device_id"
xinput list-props "$device_id" | grep -E \
  'Coordinate Transformation Matrix|libinput Calibration Matrix' || true

/usr/local/libexec/meizu-e3-map-touch-once

echo '=== touch after ==='
xinput list-props "$device_id" | grep -E \
  'Coordinate Transformation Matrix|libinput Calibration Matrix' || true

matrix=$(xinput list-props "$device_id" | awk -F: \
  '/Coordinate Transformation Matrix/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
echo "MATRIX=$matrix"
test "$matrix" = '0.360000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 1.000000'

echo '=== driver messages ==='
dmesg --color=never | grep -Ei \
  'sec_ts|Samsung Electronics Touchscreen|sgm37604a|rcu.*stall|watchdog.*lockup|Oops|panic|NULL pointer' \
  | tail -n 240
