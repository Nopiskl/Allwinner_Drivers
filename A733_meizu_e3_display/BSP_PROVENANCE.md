# BSP and reference-source provenance

The BSP directories are deliberately source snapshots, not nested Git
repositories. This keeps the archive reviewable while preserving every file
directly cited by the root-cause analysis.

## Allwinner BSP 1.4.6 reference

- Upstream: `https://github.com/radxa/allwinner-bsp.git`
- Branch: `cubie-aiot-v1.4.6`
- Commit: `2045a3ca2a01f088c0314dc924bda59d154e363e`
- Local directory: `bsp/radxa-allwinner-bsp/`

The snapshot contains the relevant sunxi DRM CRTC/connector files, TCON
dispatcher, DE/RCQ implementation, overlay address programming, IOMMU fault
handler and A733 `sun60iw2p1.dtsi`.

## Allwinner BSP 1.4.8 reference

- Upstream: `https://github.com/radxa/allwinner-bsp.git`
- Branch: `cubie-aiot-v1.4.8`
- Branch snapshot commit: `f51e1e6195d4350abc590bff852e213279e660a6`
- Release boundary referenced during analysis:
  `e1524a9d77fe5a2801ead100affea1686867d377`
- Local directory: `bsp/radxa-allwinner-bsp-v1.4.8/`

Files were fetched by immutable commit URL and match the same path list retained
for 1.4.6, allowing direct two-tree comparison without relying on later commit
history in this repository.

## Radxa A733 kernel DRM helper reference

- Upstream: `https://github.com/radxa/kernel.git`
- Branch used in the investigation: `allwinner-aiot-linux-5.15`
- Commit: `e41499895c17074874f4c48ff04041c57d8dfd99`
- Local directory: `bsp/radxa-kernel-a733/`

Only `drm_atomic_helper.c` and its public helper header are retained. The
original workspace checkout was incomplete and its approximately 254 MiB Git
object pack was never a buildable source tree, so copying that nested `.git`
would add size without improving reproducibility.

## Cubie A7A board sources

- Upstream: `https://github.com/radxa/allwinner-device.git`
- Branch: `device-a733-v1.4.6`
- Commit: `79d54f44e14111db3845096cef0639a6c9222707`
- Local directory: `bsp/radxa-allwinner-device-a733/`

Text configuration, U-Boot DTS, and the Linux 5.15/6.6 A7A board DTS files are
retained. Boot-logo and Android warning bitmaps are excluded as unrelated to
the display adaptation and root-cause evidence.

## Official Radxa overlay references

- Upstream: `https://github.com/radxa-pkg/radxa-overlays.git`
- Branch: `main`
- Workspace snapshot commit:
  `c79b70822a314a7c828d361cbe976780af45c0a3`
- Important graph fix referenced during analysis:
  `4349013e00f21b703a75d620d8589f301ffc0493`
- Local directory: `bsp/radxa-overlays-official/`

The selected files are the A7A 8HD/10FHD overlays and matching ROCK 4D
8HD/10FHD references used to derive and compare the Meizu E3 graph.

## Meizu E3 RK reference material

The `bsp/radxa-meizu-e3/` directory is the preserved community/reference
material supplied in the workspace: RK3576 panel DTS, SGM37604A and SEC touch
sources, and the original Armbian patches. Compiler intermediates were removed;
the human-authored source and hardware/reference files were retained.
