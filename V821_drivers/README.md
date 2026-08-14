# Allwinner V821 driver adaptations

This directory collects two hardware bring-up results for Allwinner V821 Tina Linux boards. The documents are written in Chinese and include the observed failure modes, source/configuration snapshots, reproducible commands, validated artifacts, and rollback procedures.

## Contents

| Directory | Target | Result |
| --- | --- | --- |
| [`lcd/`](lcd/) | V821 `avaota_f1`, P169H002-CTP, ST7789V-compatible 240×280 SPI/DBI LCD | DBI L4I1 panel driver, DTS/Kconfig/LVGL integration, source snapshot, tested kernel modules, boot image, deployment and rollback documentation |
| [`gmac/`](gmac/) | V821 `perf2b`, RTL8201F RMII PHY | Root-cause analysis for an incorrect 100Base-FX strap, a runtime UTP recovery script, and cold-/warm-boot validation guidance |

LCD entry points:

- [Porting and build record](lcd/porting/PORTING_AND_BUILD.md)
- [Archived adapted source files](lcd/porting/source_snapshot/README.md)
- [Deployment, boot backup/flash, module load and rollback](lcd/DEPLOYMENT.md)
- [KO/LVGL regression testing](lcd/MANUAL_TEST.md)

GMAC entry points:

- [RTL8201F link diagnosis and fix](gmac/GMAC_RTL8201F_LINK_DEBUG.md)
- [Step-by-step debugging walkthrough](gmac/GMAC_RTL8201F_DEBUG_WALKTHROUGH.md)
- [`gmac_recover.sh`](gmac/gmac_recover.sh): volatile runtime recovery that clears RTL8201F FXMODE and restarts auto-negotiation

## Important hardware scope

The LCD and GMAC work was validated on different V821 board configurations. Their pinmux must not be combined mechanically: the LCD DBI signals use pins in the same PD bank occupied by GMAC RMII on `perf2b`, and the board documentation also identifies a PD17 reset/GPIO reuse risk. Review the target schematic and pinctrl before enabling both functions.

The LCD `boot.img`, DTB and kernel modules are specific to the documented V821 `avaota_f1` Linux 5.4.220 build. Verify all hashes, back up the complete boot partition, and confirm the live MTD mapping before writing NOR. The package intentionally contains no automatic flash script.

The GMAC recovery script changes PHY registers at runtime. It does not replace the recommended hardware strap/assembly correction and may need to be run again after reset or power cycling.

## Repository layout and licenses

Adapted files retain their original SPDX and copyright notices. Datasheets, vendor initialization tables, firmware images and other binary artifacts remain subject to their respective upstream/vendor terms. See the documentation in each subdirectory before redistribution or use on another product.
