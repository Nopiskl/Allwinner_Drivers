# Archive scope and exclusions

The source workplace contained about 646 MiB. This repository retains the
complete adaptation history in a reviewable form, but does not duplicate large
caches and binary captures that are either reconstructible or already
represented by compact evidence.

## Retained

- All three final project documents.
- All mainline and codexline experiment documentation, source and tools.
- All compact serial, SSH, dmesg, DRM and IOMMU logs, including the decisive
  old-framebuffer and cold-boot hard-lock traces.
- All DEB revisions (`0.1.6` through `0.1.10`) and their unpacked/staging source.
- Versioned DTSO/DTBO, merged-DTB and readback artifacts used by experiments.
- Selected old/new system snapshot files: system identity, extlinux, runtime
  DTS, DRM state, backlight/input state, dmesg, DKMS/relevant package state and
  storage layout.
- Matching BSP 1.4.6 and 1.4.8 source files cited by the conclusion.
- A7A 5.15/6.6 board DTS, official Radxa display overlays, Meizu RK reference
  source, and Linux DRM helper reference.

## Excluded

| Material | Approximate original size | Reason |
|---|---:|---|
| Nested BSP/kernel/overlay `.git` directories | over 262 MiB | Git caches, not adaptation content; immutable upstream commits are recorded instead |
| Pre-T4 compressed system snapshots/portable archives | about 131 MiB | Duplicate the extracted/selected records and include a single file over GitHub's normal limit |
| Four raw XWD captures and four BMP conversions | about 173 MiB | Uncompressed duplicate framebuffer captures; textual GPU/X11 diagnosis is retained |
| Complete repeated stock/post-install journal snapshots | several MiB | Mostly duplicate boot output and local network identifiers; selected dmesg/state evidence is retained |
| Boot logos and Android warning bitmaps | about 19 MiB | Unrelated to DSI, touch, backlight or DRM failure analysis |
| `*.o`, `*.ko`, `*.cmd`, `*.i`, `*.d`, `*.pyc` and `__pycache__` from reference trees | several MiB | Build-machine-specific intermediates; source and reproducible DEB outputs are retained |

The original workplace remains the forensic master copy. This Git directory is
the portable engineering archive intended for review, reuse and publication.

## Privacy and credentials

- No private SSH key or host identity file is included.
- No API/GitHub token is included.
- No Wi-Fi configuration or plaintext PSK is included.
- Historical scripts that embedded the board's default password were changed
  to require environment variables before being committed.
- Private LAN addresses remaining in historical documents are experiment
  identifiers only and do not provide access outside the original network.
