#!/bin/bash
set -u

echo '=== time / boot ==='
date --iso-8601=seconds
cat /proc/sys/kernel/random/boot_id
uptime

echo '=== stock HDMI toggle service ==='
systemctl status hdmi-toggle-once.service --no-pager -l || true
systemctl cat hdmi-toggle-once.service || true
unit_path=$(systemctl show -p FragmentPath --value hdmi-toggle-once.service 2>/dev/null || true)
if [ -n "$unit_path" ] && [ -e "$unit_path" ]; then
    stat "$unit_path"
    dpkg-query -S "$unit_path" 2>/dev/null || true
fi

echo '=== session processes and environment ==='
ps -eo user:16,pid,etimes,args | grep -E '[X]org|[k]win_x11|[p]lasmashell'
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
if [ -z "$kwin_pid" ]; then
    echo 'NO_KWIN_X11_PID'
    exit 2
fi
tr '\0' '\n' < "/proc/$kwin_pid/environ" | grep -E '^(DISPLAY|XAUTHORITY|XDG_SESSION_TYPE|KWIN_|LIBGL_|EGL_)=' || true
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
display=${display:-:0}
if [ -z "$xauth" ] || [ ! -r "$xauth" ]; then
    echo "INVALID_XAUTHORITY=$xauth"
    exit 3
fi

echo '=== GLX/KWin live confirmation ==='
runuser -u radxa -- env DISPLAY="$display" XAUTHORITY="$xauth" glxinfo -B 2>&1 || true
runuser -u radxa -- env DISPLAY="$display" XAUTHORITY="$xauth" qdbus6 org.kde.KWin /KWin supportInformation 2>&1 | sed -n '/Compositing/,/Loaded Effects/p' || true

echo '=== capture shared X11 root pixmap ==='
rm -f /tmp/t4-root-current.xwd
runuser -u radxa -- env DISPLAY="$display" XAUTHORITY="$xauth" xwd -root -silent -out /tmp/t4-root-current.xwd
stat -c 'XWD size=%s mode=%a owner=%U:%G path=%n' /tmp/t4-root-current.xwd
sha256sum /tmp/t4-root-current.xwd

echo '=== fatal display/kernel counters after capture ==='
journalctl -k -b --no-pager | grep -Eic 'atomic.flush.*timeout|PageTable Invalid|Bug is in DE|not mapped|rcu.*stall|soft lockup|NULL pointer|kernel panic|underflow|fifo.*error|vblank.*timeout|page.flip.*timeout' || true
