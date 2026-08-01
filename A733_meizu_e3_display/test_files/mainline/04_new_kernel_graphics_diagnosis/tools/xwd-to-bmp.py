#!/usr/bin/env python3
"""Convert this run's 32-bit little-endian XWD root capture to top-down BMP."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    blob = args.source.read_bytes()
    if len(blob) < 100:
        raise SystemExit("XWD is shorter than the fixed 100-byte header")
    fields = struct.unpack(">25I", blob[:100])
    (
        header_size,
        file_version,
        pixmap_format,
        pixmap_depth,
        width,
        height,
        xoffset,
        byte_order,
        _bitmap_unit,
        _bitmap_bit_order,
        _bitmap_pad,
        bits_per_pixel,
        bytes_per_line,
        _visual_class,
        red_mask,
        green_mask,
        blue_mask,
        _bits_per_rgb,
        _colormap_entries,
        ncolors,
        *_window_geometry,
    ) = fields
    expected = {
        "file_version": (file_version, 7),
        "pixmap_format": (pixmap_format, 2),
        "pixmap_depth": (pixmap_depth, 24),
        "xoffset": (xoffset, 0),
        "byte_order": (byte_order, 0),
        "bits_per_pixel": (bits_per_pixel, 24),
        "red_mask": (red_mask, 0x00FF0000),
        "green_mask": (green_mask, 0x0000FF00),
        "blue_mask": (blue_mask, 0x000000FF),
    }
    bad = [f"{name}={actual!r}, expected {wanted!r}" for name, (actual, wanted) in expected.items() if actual != wanted]
    if bad:
        raise SystemExit("Unsupported XWD layout: " + "; ".join(bad))

    packed_line = width * 3
    if bytes_per_line < packed_line:
        raise SystemExit(f"XWD line is {bytes_per_line} bytes, shorter than {packed_line}")
    pixel_offset = header_size + ncolors * 12
    xwd_pixel_size = bytes_per_line * height
    source_pixels = blob[pixel_offset : pixel_offset + xwd_pixel_size]
    if len(source_pixels) != xwd_pixel_size:
        raise SystemExit(f"Pixel payload is {len(source_pixels)} bytes, expected {xwd_pixel_size}")
    # This Xorg/xwd pair records 24-bit BGR scanlines in a 12000-byte
    # container: 9000 bytes of pixels plus 3000 zero pad bytes per row.
    pixels = b"".join(
        source_pixels[row * bytes_per_line : row * bytes_per_line + packed_line]
        for row in range(height)
    )
    pixel_size = len(pixels)

    bmp_pixel_offset = 14 + 40
    file_size = bmp_pixel_offset + pixel_size
    file_header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, bmp_pixel_offset)
    dib_header = struct.pack(
        "<IiiHHIIiiII",
        40,
        width,
        -height,
        1,
        24,
        0,
        pixel_size,
        2835,
        2835,
        0,
        0,
    )
    args.destination.write_bytes(file_header + dib_header + pixels)
    print(f"{width}x{height}, XWD offset={pixel_offset}, BMP={args.destination}")


if __name__ == "__main__":
    main()
