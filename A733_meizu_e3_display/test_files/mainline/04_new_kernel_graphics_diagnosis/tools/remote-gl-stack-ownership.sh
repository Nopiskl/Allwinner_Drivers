#!/bin/bash
set -u
echo '=== candidates and real targets ==='
for path in \
    /usr/local/lib/libEGL.so /usr/local/lib/libEGL.so.1 \
    /usr/local/lib/libGLESv2.so /usr/local/lib/libGLESv2.so.2 \
    /usr/lib/aarch64-linux-gnu/libEGL.so.1 \
    /usr/lib/aarch64-linux-gnu/libGLX.so.0 \
    /usr/lib/aarch64-linux-gnu/libGL.so.1 \
    /lib/libpvr_mesa_wsi.so /usr/local/lib/libpvr_mesa_wsi.so; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    ls -l "$path"
    printf '  realpath=%s\n' "$(readlink -f "$path")"
    dpkg-query -S "$path" 2>/dev/null || printf '  package=unowned\n'
done

echo '=== package file list: IMG Xorg/PVR integration ==='
dpkg-query -L xserver-xorg-img-bxm-1.21.1-2.deb 2>/dev/null | sort || true
dpkg-query -L img-bxm-dkms 2>/dev/null | sort | sed -n '1,240p' || true

echo '=== loader config ==='
grep -RnsH . /etc/ld.so.conf /etc/ld.so.conf.d 2>/dev/null || true

echo '=== executable dynamic bindings ==='
for executable in /usr/bin/glxinfo /usr/bin/kwin_x11 /usr/bin/plasmashell /usr/lib/xorg/Xorg; do
    [ -x "$executable" ] || continue
    echo "--- $executable"
    ldd "$executable" 2>/dev/null | grep -Ei 'EGL|GLX|GL\.so|GLES|pvr|drm|gbm' || true
done

echo '=== available EGL diagnostics ==='
command -v eglinfo || true
if command -v eglinfo >/dev/null 2>&1; then
    kwin_pid=$(pgrep -n -u radxa kwin_x11 || true)
    display=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^DISPLAY=//p' | head -n1)
    xauth=$(tr '\0' '\n' < "/proc/$kwin_pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -n1)
    runuser -u radxa -- env DISPLAY="${display:-:0}" XAUTHORITY="$xauth" eglinfo 2>&1 | sed -n '1,280p' || true
fi
