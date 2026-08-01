#!/bin/bash
set -u
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xwininfo -id 0x400009 -tree
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xwininfo -id 0x120001a -tree
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" xwininfo -id 0x1200019 -all
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" \
    xprop -id 0x400009 _NET_WM_STATE _NET_WM_DESKTOP WM_STATE
