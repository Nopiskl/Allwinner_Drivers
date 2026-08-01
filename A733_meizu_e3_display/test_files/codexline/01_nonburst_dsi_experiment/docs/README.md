# 2026-07-31 v002 non-burst controlled test

## Starting state

- Board: Radxa A7A at `192.168.0.103`
- Kernel: `5.15.147-21-a733`
- v001 was rolled back through the official `rsetup` mechanism.
- The stock HDMI-only Plasma desktop was stable after rollback.
- The failed v001 boot reached a correct dual-screen LightDM greeter, but Plasma
  login was followed by `sunxi_de_atomic_flush` timeouts, unmapped DE0 IOMMU
  accesses, an IRQ storm, and RCU stalls.

## Hypothesis

Radxa's officially tested A7A DSI overlays use
`MIPI_DSI_MODE_VIDEO` without `MIPI_DSI_MODE_VIDEO_BURST`.  The Meizu E3 v001
overlay used `VIDEO_BURST`, which selects different timing/register branches in
the vendor DSI driver and also changes the driver's effective pixel clock.

v002 is therefore a single-variable experiment:

- remove only `MIPI_DSI_MODE_VIDEO_BURST`;
- keep the v001 `dsi0` `port@1` graph correction from Radxa commit
  `4349013e00f21b703a75d620d8589f301ffc0493`;
- keep all panel timing, lane count, pixel format, power, backlight, touch, HDMI,
  and DRM routing settings unchanged;
- make no kernel or driver changes.

The expected compiled `dsi,flags` value is `0x0a01`:

- `MIPI_DSI_MODE_VIDEO` = `0x0001`
- vendor low-power bit `(1 << 11)` = `0x0800`
- `MIPI_DSI_MODE_NO_EOT_PACKET` = `0x0200`

## Safety procedure

1. Compile the overlay on the board without installing or enabling it.
2. Apply it offline to the stock DTB with `fdtoverlay`.
3. Decompile/read back the merged DTB and verify graph, flags, timing, and HDMI.
4. Build and install the package with its DTBO left `.disabled`.
5. Enable only v002, regenerate `extlinux.conf`, and verify:
   - normal `l0` contains exactly v002;
   - rescue `l0r` contains no overlays and retains `single`.
6. Capture serial output before reboot and through Plasma login.
7. If the fault recurs, boot `l0r`, rename v002 back to `.disabled`, and run
   `u-boot-update`.

## Results

### Offline validation

- The board's own `cpp`, `dtc`, and current `5.15.147-21-a733` headers compiled
  the overlay successfully.
- `fdtoverlay` applied it successfully to the unmodified A7A DTB.
- DTBO SHA256:
  `b05d2220b31452a46ffb83940f349d1827be0d4c8e352f36b9e04fb9b0db3be2`
- Read-back values:
  - `dsi,flags = 0x0a01`
  - four lanes, RGB888
  - 1080 x 2160, 157000000 Hz; every porch and sync value unchanged
  - `dsi0/ports/port@1/reg = 1`
  - both pairs of graph endpoints are reciprocal
  - DSI0, its PHY, and HDMI0 all remain `okay`
- Compiled v001/v002 comparison shows only metadata and
  `dsi,flags 0x0a03 -> 0x0a01`.
- The same `dtc` graph/address diagnostic class is emitted by the official
  `cubie-a7a-radxa-display-10fhd.dtso`; it is not introduced by v002.

### Package and disabled installation

- Current archive name: `meizu-e3-dkms_codexline-01-nonburst-dsi-experiment_all.deb`
- Historical test filename: `meizu-e3-dkms_0.1.10_all.deb`
- Package SHA256:
  `998700ce97de18ae5fc07a754151c7d9893ef885b5abe83342af83e2191476d9`
- `meizu-e3-dkms 0.1.10` installed successfully.
- DKMS installed `sec_ts` and `sgm37604a` for `5.15.147-21-a733`.
- The installed disabled DTBO matched the offline artifact byte for byte.
- Before enablement there were zero active DTBO files, no `fdtoverlays` line,
  and zero matching display-fault messages in the current stock boot.

### Controlled enablement

- The active file is exactly
  `cubie-a7a-meizu-e3-display-v002.dtbo`.
- Normal `l0` contains only that overlay.
- Rescue `l0r` contains no `fdtoverlays` and retains `single`.
- The enabled artifact hash is unchanged.
- `/boot/extlinux/extlinux.conf.pre-meizu-v002` is the board-side pre-enable
  backup.

### First reboot attempt

`systemctl reboot` disconnected SSH, but COM4 produced no U-Boot, BootROM, or
kernel bytes during the following 48-second window. This matches the
independent vendor-platform software-reset failure previously reproduced in
stock rescue mode. It does not yet constitute a v002 boot or display result.

Physical power cycling is required before the actual v002 boot test can
continue. Use default `l0`; if the display test fails, use `l0r` and disable
v002 with the official rename plus `u-boot-update` rollback.

### Physical v002 boot result

The physical boot was captured as boot ID
`4c68a65b0087408385661fba98c7c793`. Both HDMI and DSI remained black.
The persistent kernel journal contains 1287 lines and 166 display-related
lines. There are zero occurrences of the old fatal chain:

- `sunxi_de_atomic_flush timeout`
- L1/L2 page-table invalid
- `Bug in DE`
- RCU stall
- NULL dereference or kernel panic

The early DSI sequence was:

1. `1.791252`: DSI-1 detected, 1080x2160@59 Hz.
2. `1.842307`: CRTC atomic enable started.
3. `1.843107`: `sunxi_dsi_combophy_configure start`.
4. No low-level timing line, encoder-enable finish, or
   `DSI-1: Configuration complete` followed.

This differs precisely from v001. With burst enabled, v001 printed the
low-level timing immediately after combo-PHY configuration, then printed
encoder-enable finish and DSI configuration complete at 2.591-2.600 seconds.
Therefore the non-burst v002 path stalls inside or immediately after the
vendor combo-PHY configuration path during the initial DRM atomic enable.
Because HDMI and DSI share the same DRM device/atomic commit, this explains why
HDMI also never reached a usable framebuffer even though HDMI HPD was detected.

Secondary effects in the same failed boot:

- SGM37604A register 0x11 failed to latch; backlight probe returned `-5`.
- SEC touch I2C writes failed and its probe returned `-5`.
- HDMI produced repeated PHY I2M read errors at 23.798 seconds.

These are consequences or companion failures during the incomplete display
bring-up; they are not evidence that the old DE/IOMMU crash recurred.

### Rollback

The board was booted through `l0r`, confirmed by `single` in the kernel command
line. v002 was disabled using the official mechanism:

1. rename `cubie-a7a-meizu-e3-display-v002.dtbo` to `.dtbo.disabled`;
2. run `/usr/sbin/u-boot-update`;
3. run `sync`.

Post-rollback validation:

- active DTBO count: 0
- v001 and v002 both remain `.disabled`
- disabled v002 SHA256 is unchanged
- neither `l0` nor `l0r` contains `fdtoverlays`
- `l0r` retains `single`

v002 is rejected. No further DTS candidate will be enabled until a new
evidence-backed, single-variable hypothesis is prepared and explicitly
approved.
