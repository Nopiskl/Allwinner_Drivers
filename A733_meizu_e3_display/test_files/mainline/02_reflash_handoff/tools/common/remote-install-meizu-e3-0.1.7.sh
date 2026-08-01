#!/bin/sh
set -eu

sudo -S -p "" -v

backup="/home/radxa/codex-backups/meizu-e3-before-0.1.7-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
sudo cp -a /boot/extlinux/extlinux.conf "$backup/"
sudo cp -a /boot/dtbo/cubie-a7a-meizu-e3-display.dtbo "$backup/"
dpkg-query -W meizu-e3-dkms > "$backup/package-version.txt"
/usr/sbin/dkms status -m meizu-e3-dkms > "$backup/dkms-status.txt"

printf "backup=%s\n" "$backup"
sudo apt-get install -y /home/radxa/meizu-e3-dkms_0.1.7_all.deb
