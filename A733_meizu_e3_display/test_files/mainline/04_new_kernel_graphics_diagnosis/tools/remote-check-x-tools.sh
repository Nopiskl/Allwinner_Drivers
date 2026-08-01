#!/bin/bash
set -u
for tool in xdotool wmctrl xwininfo xprop xwd xset qdbus6; do
    printf '%-10s ' "$tool"
    command -v "$tool" || true
done
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" \
    xwininfo -root -tree 2>&1 | grep -i -E 'system settings|quick settings|systemsettings' || true
