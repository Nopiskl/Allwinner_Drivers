# Allwinner Drivers and Patches

Collection of drivers, patches, and multimedia libraries for Allwinner SoCs.

## Contents

### A133_multimedia_drivers
CedarX multimedia framework libraries and demo applications for Allwinner A133 platform.

### V851s_opencv
OpenCV integration with VIN ISP support for Allwinner V851s platform, including patches and camera demos.

### A733_meizu_e3_display
End-to-end Meizu E3 1080x2160 MIPI-DSI display adaptation for Radxa Cubie A7A
(Allwinner A733): DT overlays, SGM37604A backlight, Samsung SEC touch,
versioned DKMS packages, controlled `l0`/`l0r` rollback, test logs, and a
source-backed analysis of the BSP 1.4.6 mixed TCON-LCD/TCON-TV DRM hard lock.

### V821_drivers

Validated V821 Tina Linux bring-up records for two board configurations:

- `avaota_f1`: P169H002-CTP ST7789V-compatible 240x280 SPI/DBI LCD driver,
  DTS/Kconfig/LVGL integration, source snapshot, tested boot/modules/userspace
  artifacts, and controlled ADB deployment/rollback.
- `perf2b`: RTL8201F RMII link diagnosis, 100Base-FX strap root cause, runtime
  UTP recovery script, and permanent hardware/configuration guidance.

See [`V821_drivers/README.md`](V821_drivers/README.md) for hardware-scope and
pinmux warnings before using these adaptations together.

### VE_drivers

Cedrus Linux V4L2 hardware video decoder drivers for Allwinner A733, T527, and
F101. Each platform directory contains codec implementations, hardware control,
and Kbuild configuration. F101 also includes a dedicated JPEG decoder.

See [`VE_drivers/README.md`](VE_drivers/README.md) for platform capabilities,
directory layout, and kernel integration requirements.

## Requirements

- Allwinner TinaSDK or a compatible target Linux kernel build environment
- Target hardware: A133, A733, T527, F101, V821, or V851s based boards

## License

Refer to individual component directories for specific license information.
