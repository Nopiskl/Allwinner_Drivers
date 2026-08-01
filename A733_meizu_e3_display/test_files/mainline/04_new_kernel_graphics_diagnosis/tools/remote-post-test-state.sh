#!/bin/bash
set -u
date --iso-8601=seconds
cat /proc/sys/kernel/random/boot_id
echo '=== processes ==='
ps -eo user:12,pid,etimes,state,args | grep -E '[X]org|[k]win_x11|[p]lasmashell'
echo '=== connector enabled/dpms/status ==='
for connector in /sys/class/drm/card0-*; do
    [ -d "$connector" ] || continue
    printf '%s status=' "$(basename "$connector")"
    cat "$connector/status" 2>/dev/null || printf '?\n'
    for item in enabled dpms; do
        [ -r "$connector/$item" ] && printf '  %s=%s\n' "$item" "$(cat "$connector/$item")"
    done
done
echo '=== CRTC activity ==='
grep -E '^crtc\[|^[[:space:]]*(active|enable|mode):' /sys/kernel/debug/dri/0/state 2>/dev/null || true
echo '=== X11 current/DPMS ==='
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xrandr --current 2>&1 || true
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xset q 2>&1 | sed -n '/DPMS/,/Monitor is/p' || true
echo '=== kernel since redraw test ==='
journalctl -k -b --since '2026-07-31 13:32:30 UTC' --no-pager 2>/dev/null | \
    grep -Ei 'drm|dsi|hdmi|display|de[0-9]|iommu|pvr|underflow|fifo|timeout|rcu.*stall|soft lockup|NULL pointer|panic' || true
