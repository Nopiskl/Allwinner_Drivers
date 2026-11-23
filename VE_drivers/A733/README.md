# A733 Cedrus Driver

Linux V4L2 hardware video decoder integration for the Allwinner A733 Video
Engine. The driver implements SUN60I-specific engine initialization and power
management alongside the Cedrus codec and buffer-management paths.

## Features

- MPEG-2, H.264, H.265, H.265 10-bit, and VP8 decode capabilities.
- SUN60I engine mode configuration and VCU reset after clock enable.
- A default VE module clock of 624 MHz.
- Optional AHB and MBUS gate clocks with enable-failure cleanup.
- Device-tree clock-name selection that preserves deferred-probe errors.
- Frame-size enumeration and linear NV12, NV21, YUV420, and YVU420 output formats.
- SUN60I operation without the legacy SRAM claim sequence.

## Platform Integration

The A733 platform entry matches `allwinner,sun60i-video-engine`.

| Resource | Configuration |
| --- | --- |
| Bus clock | `bus_ve`, or `ahb` when only the legacy name is declared |
| Module clock | `ve`, or `mod` when only the legacy name is declared |
| Memory-bus clock | `mbus_ve`, or `ram` when only the legacy name is declared |
| Optional gate clocks | `ahb_gate`, `mbus_gate` |
| Registers | VE MMIO region covering the VCU reset register at offset `0x804` |
| Interrupt and reset | First platform IRQ and the default reset control |

The implementation uses Linux 6.19-era media APIs. The target kernel must
provide the V4L2, Media Controller, Video Buffer 2, and SUNXI SRAM interfaces
referenced by the driver. SUNXI SRAM remains a build dependency because the
source also contains support for older Allwinner devices.

## Source and Build

`cedrus/` contains the complete driver sources and Kbuild configuration.
Its Makefile supports both in-tree Kbuild and external-module builds against
a prepared, compatible kernel. The module is named `sunxi-cedrus`.

The capability flags and default clock describe the driver configuration;
board-level operation and stream compatibility require target-hardware testing.
