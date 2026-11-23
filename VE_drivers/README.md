# Allwinner Video Engine Drivers

A collection of Cedrus Linux drivers for hardware video decoding on Allwinner
A733, T527, and F101 platforms. Each platform has its own driver directory,
including codec implementations, hardware control, V4L2 integration, and Kbuild
configuration.

The project provides source code for kernel and board integration. The drivers
use the Linux V4L2 memory-to-memory interface to expose the Video Engine to
compatible multimedia applications.

## Platforms

| Platform | Decode paths enabled by the platform variant | Key features |
| --- | --- | --- |
| [A733](A733/README.md) | MPEG-2, H.264, H.265, H.265 10-bit, VP8 | SUN60I engine control, VCU reset, optional bus gates, and flexible DT clock names |
| [T527](T527/README.md) | MPEG-2, H.264, H.265, VP8 | BSP integration, configurable VE clock, IOMMU handling, and DMA-SG capture buffers |
| [F101](F101/README.md) | H.264, JPEG | F101 engine mode handling, JPEG decoding, and tiled-to-linear image conversion |

These entries describe the capabilities selected in the driver code. Actual
availability depends on the target kernel, board resources, and userspace codec
support.

## Directory Layout

```text
VE_drivers/
├── A733/
│   ├── README.md
│   └── cedrus/
├── T527/
│   ├── README.md
│   └── cedrus/
├── F101/
│   ├── README.md
│   └── cedrus/
└── README.md
```

Every `cedrus/` directory contains:

- `cedrus.c` and `cedrus.h`: device registration, platform variants, controls, and shared state.
- `cedrus_video.c` and `cedrus_dec.c`: V4L2 formats, buffer queues, and decode job handling.
- `cedrus_hw.c` and `cedrus_regs.h`: clocks, resets, interrupts, and hardware registers.
- `cedrus_*.c`: codec-specific decoding implementations.
- `Kconfig` and `Makefile`: kernel configuration and build integration.

F101 also includes `cedrus_jpeg.c` for its JPEG decode path.

## Kernel Integration

Choose the driver directory for the target SoC and integrate it with a matching
Linux kernel build environment. The platform directories are separate driver
implementations; they are not interchangeable modules for every kernel version.

The target kernel must provide the V4L2 and Media Controller frameworks,
Video Buffer 2, DMA support, clocks, resets, and the platform services selected
by the driver's `Kconfig`. The board device tree must describe the VE register
range, interrupt, clocks, and reset resources.

Build the selected driver through Kbuild with `CONFIG_VIDEO_SUNXI_CEDRUS`.
The resulting kernel module is named `sunxi-cedrus`. Platform-specific details,
including device-tree matching and additional dependencies, are documented in
each platform directory. Prebuilt modules and board device trees are not included.

## License

Driver source files retain their GPL-2.0 SPDX identifiers and copyright notices.
Refer to the license declarations in individual files.
