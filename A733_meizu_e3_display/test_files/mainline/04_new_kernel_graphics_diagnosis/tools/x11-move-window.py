#!/usr/bin/env python3
"""Transiently move one X11 window for a redraw diagnostic, then restore it."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import math
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--window", required=True, type=lambda value: int(value, 0))
    parser.add_argument("--seconds", type=float, default=8.0)
    parser.add_argument("--interval", type=float, default=0.05)
    parser.add_argument("--raise-only", action="store_true")
    args = parser.parse_args()

    x11 = ctypes.CDLL(ctypes.util.find_library("X11"))
    display_p = ctypes.c_void_p
    window_t = ctypes.c_ulong
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = display_p
    x11.XDefaultRootWindow.argtypes = [display_p]
    x11.XDefaultRootWindow.restype = window_t
    x11.XQueryTree.argtypes = [
        display_p,
        window_t,
        ctypes.POINTER(window_t),
        ctypes.POINTER(window_t),
        ctypes.POINTER(ctypes.POINTER(window_t)),
        ctypes.POINTER(ctypes.c_uint),
    ]
    x11.XGetGeometry.argtypes = [
        display_p,
        window_t,
        ctypes.POINTER(window_t),
        ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_uint),
        ctypes.POINTER(ctypes.c_uint),
        ctypes.POINTER(ctypes.c_uint),
        ctypes.POINTER(ctypes.c_uint),
    ]
    x11.XMoveWindow.argtypes = [display_p, window_t, ctypes.c_int, ctypes.c_int]
    x11.XRaiseWindow.argtypes = [display_p, window_t]
    x11.XSync.argtypes = [display_p, ctypes.c_int]
    x11.XFree.argtypes = [ctypes.c_void_p]
    x11.XCloseDisplay.argtypes = [display_p]

    display = x11.XOpenDisplay(None)
    if not display:
        raise SystemExit("XOpenDisplay failed")
    root = x11.XDefaultRootWindow(display)
    current = window_t(args.window)
    chain = [current.value]
    while current.value != root:
        root_ret = window_t()
        parent_ret = window_t()
        children = ctypes.POINTER(window_t)()
        nchildren = ctypes.c_uint()
        if not x11.XQueryTree(display, current, ctypes.byref(root_ret), ctypes.byref(parent_ret), ctypes.byref(children), ctypes.byref(nchildren)):
            raise SystemExit(f"XQueryTree failed for 0x{current.value:x}")
        if children:
            x11.XFree(children)
        if parent_ret.value == root:
            break
        if not parent_ret.value or parent_ret.value in chain:
            raise SystemExit("Invalid/cyclic X11 parent chain")
        current = parent_ret
        chain.append(current.value)
    frame = current

    geometry_root = window_t()
    x = ctypes.c_int()
    y = ctypes.c_int()
    width = ctypes.c_uint()
    height = ctypes.c_uint()
    border = ctypes.c_uint()
    depth = ctypes.c_uint()
    if not x11.XGetGeometry(
        display,
        frame,
        ctypes.byref(geometry_root),
        ctypes.byref(x),
        ctypes.byref(y),
        ctypes.byref(width),
        ctypes.byref(height),
        ctypes.byref(border),
        ctypes.byref(depth),
    ):
        raise SystemExit(f"XGetGeometry failed for frame 0x{frame.value:x}")
    original = (x.value, y.value)
    print(
        f"client=0x{args.window:x} frame=0x{frame.value:x} "
        f"chain={[hex(item) for item in chain]} geometry={width.value}x{height.value}+{x.value}+{y.value}",
        flush=True,
    )

    if args.raise_only:
        x11.XRaiseWindow(display, frame)
        x11.XSync(display, 0)
        x11.XCloseDisplay(display)
        print("raised=yes", flush=True)
        return

    started = time.monotonic()
    try:
        while time.monotonic() - started < args.seconds:
            elapsed = time.monotonic() - started
            phase = (math.sin(elapsed * math.tau / 1.6) + 1.0) / 2.0
            new_x = round(1120 + phase * 900)
            new_y = round(90 + phase * 120)
            x11.XMoveWindow(display, frame, new_x, new_y)
            x11.XSync(display, 0)
            time.sleep(args.interval)
    finally:
        x11.XMoveWindow(display, frame, original[0], original[1])
        x11.XSync(display, 0)
        x11.XCloseDisplay(display)
        print(f"restored=+{original[0]}+{original[1]}", flush=True)


if __name__ == "__main__":
    main()
