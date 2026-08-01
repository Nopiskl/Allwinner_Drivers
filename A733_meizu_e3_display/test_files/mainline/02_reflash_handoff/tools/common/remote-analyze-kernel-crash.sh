#!/bin/sh
set -u

IFS= read -r sudo_password

sudo_run()
{
	printf "%s\n" "$sudo_password" | sudo -S -p "" "$@"
}

count_pattern()
{
	boot="$1"
	pattern="$2"
	sudo_run journalctl -k -b "$boot" --no-pager |
		grep -c "$pattern" || true
}

printf "previous_iommu_warnings="
count_pattern -1 "sunxi_iommu_irq"
printf "previous_hdmi_detects="
count_pattern -1 "drm hdmi detect"
printf "current_iommu_warnings="
count_pattern 0 "sunxi_iommu_irq"
printf "current_hdmi_detects="
count_pattern 0 "drm hdmi detect"

printf "\n===== previous boot final 180 kernel records =====\n"
sudo_run journalctl -k -b -1 -o short-monotonic --no-pager | tail -n 180

printf "\n===== previous boot IOMMU/DRM contexts =====\n"
sudo_run journalctl -k -b -1 -o short-monotonic --no-pager |
	grep -E -B 12 -A 32 "WARNING:.*sunxi-iommu|sunxi_iommu_irq|SUNXI DRM DEBUG" |
	tail -n 320

printf "\n===== current boot first IOMMU/DRM contexts =====\n"
sudo_run journalctl -k -b 0 -o short-monotonic --no-pager |
	grep -E -B 12 -A 32 "WARNING:.*sunxi-iommu|sunxi_iommu_irq|SUNXI DRM DEBUG" |
	head -n 320
