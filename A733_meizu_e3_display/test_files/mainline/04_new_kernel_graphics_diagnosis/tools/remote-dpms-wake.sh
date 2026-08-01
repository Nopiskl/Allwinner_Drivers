#!/bin/bash
set -u
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xset dpms force on
sleep 3
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xset q | sed -n '/DPMS/,/Monitor is/p'
for connector in /sys/class/drm/card0-DSI-1 /sys/class/drm/card0-HDMI-A-1; do
    printf '%s status=%s enabled=%s dpms=%s\n' \
        "$(basename "$connector")" \
        "$(cat "$connector/status")" \
        "$(cat "$connector/enabled")" \
        "$(cat "$connector/dpms")"
done
