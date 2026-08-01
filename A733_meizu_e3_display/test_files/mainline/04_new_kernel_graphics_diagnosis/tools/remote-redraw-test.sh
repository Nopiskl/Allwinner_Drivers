#!/bin/bash
set -u
kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
session_env=(env DISPLAY="${display:-:0}" XAUTHORITY="$xauth")

rm -f /tmp/t4-root-during-move.xwd /tmp/t4-root-after-move.xwd
runuser -u radxa -- "${session_env[@]}" \
    python3 /tmp/x11-move-window.py --window 0x400009 --seconds 8 --interval 0.04 &
mover_pid=$!
sleep 2
runuser -u radxa -- "${session_env[@]}" xwd -root -silent -out /tmp/t4-root-during-move.xwd
wait "$mover_pid"
sleep 1
runuser -u radxa -- "${session_env[@]}" xwd -root -silent -out /tmp/t4-root-after-move.xwd
stat -c 'XWD size=%s owner=%U:%G path=%n' /tmp/t4-root-during-move.xwd /tmp/t4-root-after-move.xwd
sha256sum /tmp/t4-root-during-move.xwd /tmp/t4-root-after-move.xwd
