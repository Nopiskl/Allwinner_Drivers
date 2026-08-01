# A733 Meizu E3 display adaptation

This directory archives the complete engineering path used to adapt a Meizu E3
1080x2160 MIPI-DSI panel to the Radxa Cubie A7A (Allwinner A733), including the
backlight and touchscreen integration, controlled boot rollback, experiment
timeline, failure evidence, and BSP-level root-cause analysis.

## Result

- The panel graph, panel initialization and DSI link were validated with the
  versioned `v001-reg1` overlay derived from Radxa's official A7A display
  overlay structure.
- SGM37604A backlight and Samsung SEC touch were ported through DKMS; the T4
  Linux 6.6 test also includes the adjusted touch-to-output mapping.
- On the old `5.15.147-21-a733` / BSP 1.4.6 generation, single DSI and single
  HDMI work, while a cold-boot HDMI+DSI login transition can leave DE0 scanning
  an already-unmapped framebuffer. The resulting IOMMU interrupt storm causes
  RCU stalls and a full-system lock.
- Factory information and source topology identify the primary old-BSP trigger
  as the trial DRM implementation's mixed `TCON-LCD + TCON-TV` transaction.
  BSP 1.4.8/T4 avoids the reproduced failure path.

The evidence and confidence boundaries are documented in
[`docs/FINAL_CONCLUSION.md`](docs/FINAL_CONCLUSION.md).

## Directory layout

```text
A733_meizu_e3_display/
├── docs/
│   ├── FINAL_CONCLUSION.md
│   ├── TEST_TIMELINE.md
│   └── RESCUE_BOOT_AND_ROLLBACK.md
├── test_files/
│   ├── mainline/       # controlled official-structure validation path
│   └── codexline/      # isolated exploratory experiments
├── deb/
│   ├── mainline/       # package evolution 0.1.6 through 0.1.9
│   └── codexline/      # rejected non-burst 0.1.10 experiment
├── bsp/
│   ├── radxa-allwinner-bsp/          # selected BSP 1.4.6 evidence
│   ├── radxa-allwinner-bsp-v1.4.8/   # matching BSP 1.4.8 evidence
│   ├── radxa-allwinner-device-a733/  # A7A 5.15/6.6 board DTS
│   ├── radxa-kernel-a733/            # standard DRM helper reference
│   ├── radxa-meizu-e3/               # RK reference driver/panel sources
│   └── radxa-overlays-official/      # official RK/A733 display overlays
├── ARCHIVE_SCOPE.md
└── BSP_PROVENANCE.md
```

## Test sequence

The main controlled path is:

1. Original package inspection and stock HDMI baseline.
2. Official-graph `v001-reg1` overlay validation on the old 5.15 image.
3. Non-burst and push-pull experiments, both rejected as hard-lock fixes.
4. Reflash handoff with U-Boot, extlinux, DTBO and rescue records preserved.
5. T4/Linux 6.6 validation with the same initial overlay direction.
6. Backlight/touch integration and GPU/X11 trailing diagnosis.
7. Old-kernel single-DSI cross-check.
8. Old-kernel HDMI+DSI cold-boot cross-check and source-level conclusion.

See [`docs/TEST_TIMELINE.md`](docs/TEST_TIMELINE.md) for the exact chronology and
the matching directory for every experiment.

## Safe boot model

Radxa's generated extlinux configuration provides two entries:

```text
l0  = normal/test entry, with the single versioned test overlay
l0r = rescue target, no test overlay, kernel command line contains single
```

This repository did not invent `l0r`; it formalized validation and rollback
around Radxa's existing recovery entry. Always verify the actual menu after a
new image is installed. The old R6 image used menu item `2`, but that number is
not a cross-version contract.

Full history and commands are in
[`docs/RESCUE_BOOT_AND_ROLLBACK.md`](docs/RESCUE_BOOT_AND_ROLLBACK.md).

## Package warning

The DEB files are reproducibility artifacts, not a promise that every version
is suitable for deployment:

- `0.1.9` is the official-graph mainline package used for the controlled
  `v001-reg1` direction.
- The Linux 6.6 driver port and touch mapping files are archived under
  `test_files/mainline/03_new_kernel_overlay_validation/src/driver-port-6.6/`.
- `0.1.10` removes DSI burst mode and was rejected by experiment; do not treat
  it as a newer recommended release merely because its version is larger.

Before installing anything, confirm the running kernel headers, inspect the
overlay source, preserve an overlay-free `l0r`, and stage the DTBO as
`.dtbo.disabled` until the offline merge and rollback checks pass.

## Archive policy

All source, documents, package revisions, scripts, compact logs and decisive
failure traces are retained. Redundant nested Git databases, large compressed
machine snapshots, raw XWD/BMP frame dumps and compiler intermediates are not
committed. Selected state files from the system snapshots are retained instead.
See [`ARCHIVE_SCOPE.md`](ARCHIVE_SCOPE.md) for the exact boundary.

No plaintext board password, SSH private key, Wi-Fi credential or API token is
stored in this archive. Historical automation was sanitized to obtain secrets
from environment variables.

## Licensing

This archive combines original integration material with source excerpts from
Radxa, Allwinner and Samsung-origin drivers. Retain the SPDX/copyright headers
in each source file and consult the upstream repository license for each
component. The provenance of every external source snapshot is recorded in
[`BSP_PROVENANCE.md`](BSP_PROVENANCE.md).
