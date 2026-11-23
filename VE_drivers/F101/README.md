# F101 Cedrus Driver

Linux V4L2 hardware decoding for the Allwinner F101 Video Engine, including
H.264 and baseline JPEG decoding with image-layout conversion.

## Features

- H.264 and JPEG capabilities selected by the F101 platform variant.
- A dedicated JPEG implementation in `cedrus_jpeg.c`.
- F101-specific inverted engine-mode handling.
- Hardware conversion of tiled image data to linear NV12.
- A default VE module clock of 300 MHz.

## Platform Integration

The F101 platform entry matches `allwinner,sun252i-f101-video-engine`.
The driver uses the `ahb`, `mod`, and `ram` clock names and requires the
corresponding VE MMIO, interrupt, reset, and SRAM-controller resources.

The target kernel must provide compatible V4L2 and Media Controller APIs,
Video Buffer 2 DMA-contiguous buffers, and the Allwinner platform services
selected by the driver's Kconfig. Board device-tree and clock-controller
integration are supplied by the target kernel.

The driver directory also contains the common Cedrus MPEG-2, H.265, and VP8
implementations for other platform variants. Their presence does not enable
those codecs for the F101 variant.

## Source and Build

`cedrus/` contains the driver sources, headers, Kconfig, and Makefile.
The Kbuild object list includes `cedrus_jpeg.o` alongside the common Cedrus
objects. Enable `CONFIG_VIDEO_SUNXI_CEDRUS` through a compatible target kernel;
the module is named `sunxi-cedrus`.

Decode behavior and image-format compatibility should be evaluated with the
intended board and multimedia applications.
