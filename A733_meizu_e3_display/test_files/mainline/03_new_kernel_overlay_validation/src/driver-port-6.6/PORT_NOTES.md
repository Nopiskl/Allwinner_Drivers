# Meizu E3 drivers for Radxa A7A t4 / Linux 6.6

Source behavior is based on `meizu-e3-dkms 0.1.10`, which retains the SEC
touch implementation used by the first working v001 test and the SGM37604A
initialization/readback fixes developed before the later DSI/I2C experiments.

Only Linux API compatibility was changed:

- SEC IRQ acquisition uses the original `sec,irq_gpio` +
  `of_get_named_gpio()` path because Linux 6.6 removed
  `devm_gpiod_get_from_of_node()`.
- SEC and SGM probe callbacks use the one-argument I2C callback on Linux 6.3+.
- The DKMS package is renamed to `meizu-e3-drivers-t4` to avoid colliding with
  the old 5.15 package.

The archive intentionally excludes every overlay.  Installing it cannot
modify `/boot`, `extlinux.conf`, the active v001 DTBO, or the software
`i2c-gpio` topology.

Touch mapping wraps Radxa's stock `radxa-map-tp` and adds the device name
`Samsung Electronics Touchscreen 1223`.  It runs once at SDDM/session start;
the old two-second polling loop is not installed.
