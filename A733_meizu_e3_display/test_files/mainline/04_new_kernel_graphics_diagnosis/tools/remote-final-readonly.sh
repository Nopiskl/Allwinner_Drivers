#!/bin/bash
set -u

echo '=== boot / uptime ==='
date --iso-8601=seconds
cat /proc/sys/kernel/random/boot_id
uptime

echo '=== graphics packages ==='
dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null | \
    grep -Ei '(^|:)(libegl|libgl|libgles|mesa|xserver-xorg|xwayland|kwin|plasma|pvr|img-|glamor)' | sort || true

echo '=== GL/EGL library resolution ==='
ldconfig -p 2>/dev/null | grep -Ei 'lib(EGL|GLX|GLES|GL\.so|pvr)' || true
find /usr/lib /lib -maxdepth 4 -type l \( -iname 'libEGL.so*' -o -iname 'libGLX.so*' -o -iname 'libGL.so*' \) \
    -printf '%p -> %l\n' 2>/dev/null | sort || true

echo '=== stock HDMI workaround executable ==='
stat /usr/bin/hdmi-toggle-once 2>/dev/null || true
dpkg-query -S /usr/bin/hdmi-toggle-once /usr/lib/systemd/system/hdmi-toggle-once.service 2>/dev/null || true
sed -n '1,240p' /usr/bin/hdmi-toggle-once 2>/dev/null || true

echo '=== post-redraw kernel fatal counts ==='
kernel_log=$(journalctl -k -b --no-pager 2>/dev/null || dmesg)
for expression in \
    'sunxi_de_atomic_flush.*timeout' \
    'PageTable Invalid' \
    'Bug is in DE' \
    'is not mapped' \
    'rcu.*stall' \
    'soft lockup' \
    'NULL pointer' \
    'Kernel panic' \
    'underflow' \
    'fifo.*error' \
    'vblank.*timeout' \
    'page.?flip.*timeout'; do
    count=$(printf '%s\n' "$kernel_log" | grep -Eic "$expression" || true)
    printf '%-36s %s\n' "$expression" "$count"
done

echo '=== recent kernel display tail ==='
printf '%s\n' "$kernel_log" | grep -Ei 'drm|dsi|hdmi|display|de[0-9]|iommu|pvr|underflow|fifo|timeout|rcu.*stall|soft lockup|NULL pointer|panic' | tail -n 160 || true
