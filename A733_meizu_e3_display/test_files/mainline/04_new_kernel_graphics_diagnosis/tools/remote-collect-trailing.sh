set -u

echo '=== identity ==='
date --iso-8601=seconds
uname -a
uptime
printf 'BOOT_ID='; cat /proc/sys/kernel/random/boot_id
printf 'CMDLINE='; cat /proc/cmdline

echo '=== boot overlay hashes ==='
grep -nE '^(default|label|[[:space:]]+fdtoverlays)' /boot/extlinux/extlinux.conf || true
sha256sum /boot/extlinux/extlinux.conf \
  /boot/dtbo/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo 2>&1 || true

echo '=== modules and I2C binding ==='
/usr/sbin/dkms status 2>&1 || true
lsmod | grep -E '^(sec_ts|sgm37604a|sunxi|drm|gpu|mali)' || true
for dev in 0-0036 0-0048; do
  printf '%s compatible=' "$dev"
  tr '\0' ' ' < "/sys/bus/i2c/devices/$dev/of_node/compatible" 2>/dev/null || true
  printf ' driver='
  readlink "/sys/bus/i2c/devices/$dev/driver" 2>/dev/null || echo unbound
done
cat /etc/modules-load.d/meizu-e3-drivers.conf 2>/dev/null || true
cat /etc/modprobe.d/meizu-e3-sec-ts-quarantine.conf 2>/dev/null || true

echo '=== DRM sysfs connectors ==='
for connector in /sys/class/drm/card*-*; do
  test -d "$connector" || continue
  echo "--- $connector"
  for attr in status enabled dpms link_status modes; do
    test -r "$connector/$attr" && printf '%s=' "$attr" && cat "$connector/$attr"
  done
done

echo '=== DRM debug state ==='
for dri in /sys/kernel/debug/dri/*; do
  test -d "$dri" || continue
  echo "--- $dri/name"; cat "$dri/name" 2>/dev/null || true
  for f in state clients framebuffer gem_names; do
    if test -r "$dri/$f"; then
      echo "--- $dri/$f"
      cat "$dri/$f"
    fi
  done
done

echo '=== display interrupts ==='
grep -Ei 'de|drm|dsi|tcon|lcd|hdmi|iommu|mali|gpu|vblank' /proc/interrupts || true

echo '=== backlight ==='
for b in /sys/class/backlight/*; do
  test -d "$b" || continue
  echo "--- $b -> $(readlink -f "$b/device")"
  for a in type brightness actual_brightness max_brightness bl_power; do
    test -r "$b/$a" && printf '%s=' "$a" && cat "$b/$a"
  done
done

echo '=== desktop process/session ==='
loginctl list-sessions --no-legend 2>&1 || true
loginctl show-user radxa 2>&1 || true
ps -eo user,pid,tid,psr,pcpu,stat,etimes,args --sort=-pcpu | head -n 80
echo '--- radxa environment subset'
pid=$(pgrep -u radxa -n plasmashell 2>/dev/null || true)
if test -n "$pid"; then
  tr '\0' '\n' < "/proc/$pid/environ" | grep -E \
    '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|KWIN|QT_|LIBGL|GBM|MESA)' || true
fi

auth=$(ps -eo args | awk '
  /\/usr\/bin\/X / {
    for (i = 1; i <= NF; i++)
      if ($i == "-auth") { print $(i + 1); exit }
  }')
echo "XAUTHORITY_DISCOVERED=$auth"
if test -n "$auth" && test -r "$auth"; then
  export DISPLAY=:0 XAUTHORITY="$auth"
  echo '=== X11 xrandr ==='
  xrandr --query 2>&1 || true
  echo '=== X11 xrandr verbose ==='
  xrandr --verbose 2>&1 || true
  echo '=== X11 providers ==='
  xrandr --listproviders 2>&1 || true
  echo '=== X11 DPMS ==='
  xset q 2>&1 || true
  echo '=== X11 display details ==='
  xdpyinfo 2>&1 | grep -E \
    'name of display|version number|dimensions:|resolution:|depths|number of extensions' || true
  echo '=== OpenGL renderer ==='
  glxinfo -B 2>&1 || true
  echo '=== screenshot tools ==='
  for tool in xwd import spectacle scrot maim ffmpeg; do
    command -v "$tool" 2>/dev/null || true
  done
fi

echo '=== KWin support information ==='
for qdbus in qdbus6 qdbus-qt6 qdbus; do
  if command -v "$qdbus" >/dev/null 2>&1; then
    runuser -u radxa -- env \
      DISPLAY=:0 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      "$qdbus" org.kde.KWin /KWin supportInformation 2>&1 || true
    break
  fi
done

echo '=== KWin/Xorg configuration ==='
for f in \
  /home/radxa/.config/kwinrc \
  /home/radxa/.config/kwinoutputconfig.json \
  /home/radxa/.config/kscreenlockerrc \
  /var/log/Xorg.0.log \
  /home/radxa/.local/share/xorg/Xorg.0.log; do
  if test -r "$f"; then
    echo "--- $f"
    sed -n '1,1000p' "$f"
  fi
done
echo '--- kscreen files'
find /home/radxa/.local/share/kscreen -maxdepth 3 -type f -print -exec sed -n '1,500p' {} \; 2>/dev/null || true

echo '=== KWin/Xorg current journal ==='
journalctl -b --no-pager 2>&1 | grep -Ei \
  'kwin|plasmashell|xorg|glamor|egl|opengl|llvmpipe|damage|present|page.?flip|vblank|drm|dsi|hdmi|de[0-9]|iommu|framebuffer|underflow|fifo|timeout|stale|rcu.*stall|soft lockup|watchdog|Oops|panic|NULL pointer' \
  | tail -n 1800 || true

echo '=== kernel display fault counts ==='
kernel_log=$(mktemp)
dmesg --color=never > "$kernel_log"
for pattern in \
  'sunxi_de_atomic_flush.*timeout' \
  'PageTable Invalid' \
  'Bug is in DE' \
  'is not mapped' \
  'rcu.*stall' \
  'soft lockup' \
  'NULL pointer' \
  'kernel panic' \
  'underflow' \
  'fifo.*(error|empty|full)' \
  'vblank.*(timeout|failed)' \
  'page.?flip.*(timeout|failed)' \
  'dsi.*(error|failed|timeout)'; do
  printf '%-38s ' "$pattern"
  grep -Eic "$pattern" "$kernel_log" || true
done
echo '=== kernel display timeline ==='
grep -Ei \
  'drm|dsi|hdmi|tcon|display.engine|iommu|PageTable|Bug is in DE|not mapped|underflow|fifo|vblank|page.?flip|atomic.*timeout|rcu.*stall|soft lockup|watchdog|Oops|panic|NULL pointer|sec_ts|sgm37604a' \
  "$kernel_log" | tail -n 1200 || true
rm -f "$kernel_log"
