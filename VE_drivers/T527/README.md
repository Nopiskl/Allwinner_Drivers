# T527 Cedrus Driver

Cedrus V4L2 hardware video decoding for Allwinner T527 (sun55iw3), with BSP
integration for platforms such as the Orange Pi 4A.

## Features

- MPEG-2, H.264, H.265, and VP8 decode capabilities.
- A default VE module clock of 792 MHz.
- A `clk_hz` module parameter for selecting a different VE clock rate.
- DMA-SG capture buffers with cacheable CPU mappings.
- T527 IOMMU handling and operation without the legacy SRAM claim sequence.
- Platform-specific H.264 buffer handling and decode-completion behavior.

## Platform Integration

The T527 platform entry matches `allwinner,sunxi-cedar-ve` and uses the
`ahb`, `mod`, and `ram` clock names.

This implementation targets BSP Linux 5.15 media APIs. It requires the BSP's
IOMMU interface, including `<sunxi-iommu.h>`, as well as the standard V4L2,
Media Controller, and Video Buffer 2 components. The IOMMU header and its
implementation are supplied by the target BSP, not by this driver directory.

The board device tree must provide the correct VE register range, interrupt,
clock and reset resources, and IOMMU configuration. Porting to another kernel
requires matching its media, DMA, and platform interfaces.

## Source and Build

`cedrus/` contains the driver C sources, headers, Kconfig, and Makefile.
Use the target kernel's Kbuild configuration to enable
`CONFIG_VIDEO_SUNXI_CEDRUS`; the module is named `sunxi-cedrus`.

The clock parameter and codec capabilities describe the implementation.
Choose clock rates and validate decoding on the actual board.
