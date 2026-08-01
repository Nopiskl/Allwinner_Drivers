#!/bin/bash
set -u
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" \
    python3 /tmp/x11-move-window.py --window 0x400009 --raise-only
sleep 1
runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" \
    xwd -root -screen -silent -out /tmp/t4-root-restored.xwd
stat -c 'XWD size=%s owner=%U:%G path=%n' /tmp/t4-root-restored.xwd
sha256sum /tmp/t4-root-restored.xwd
