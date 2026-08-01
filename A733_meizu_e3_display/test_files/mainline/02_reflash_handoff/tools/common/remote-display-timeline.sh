#!/bin/sh
set -u

IFS= read -r sudo_password

sudo_run()
{
	printf "%s\n" "$sudo_password" | sudo -S -p "" "$@"
}

printf "===== previous boot display/power timeline =====\n"
sudo_run journalctl -k -b -1 -o short-monotonic --no-pager |
	grep -E -i "axp8191-bldo2|axp8191-bldo5|sunxi_de_atomic_flush|PageTable Invalid|Bug is in DE0|sunxi_iommu_irq|hdmi drv detect hpd|drm hdmi detect|atomic disable|sunxi_crtc_atomic"

printf "\n===== current boot display/power timeline =====\n"
sudo_run journalctl -k -b 0 -o short-monotonic --no-pager |
	grep -E -i "axp8191-bldo2|axp8191-bldo5|sunxi_de_atomic_flush|PageTable Invalid|Bug is in DE0|sunxi_iommu_irq|hdmi drv detect hpd|drm hdmi detect|atomic disable|sunxi_crtc_atomic" |
	head -n 500

printf "\n===== regulator summary subset =====\n"
sudo_run grep -E -B 2 -A 2 "bldo2|bldo5|dc1sw1" /sys/kernel/debug/regulator/regulator_summary || true
