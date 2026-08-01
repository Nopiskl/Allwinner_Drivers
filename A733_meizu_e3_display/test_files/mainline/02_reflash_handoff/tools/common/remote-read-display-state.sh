#!/bin/sh
set -u

IFS= read -r sudo_password

sudo_run()
{
	printf "%s\n" "$sudo_password" | sudo -S -p "" "$@"
}

kernel_count()
{
	pattern="$1"
	sudo_run journalctl -k -b 0 --no-pager |
		grep -c "$pattern" || true
}

printf "sample_start=%s\n" "$(date -Is)"
printf "hdmi_detect_count="
kernel_count "drm hdmi detect"
printf "iommu_irq_count="
kernel_count "sunxi_iommu_irq"
sleep 6
printf "sample_end=%s\n" "$(date -Is)"
printf "hdmi_detect_count="
kernel_count "drm hdmi detect"
printf "iommu_irq_count="
kernel_count "sunxi_iommu_irq"

printf "\n===== backlight sysfs =====\n"
for dev in /sys/class/backlight/*; do
	printf "%s\n" "$dev"
	for property in brightness actual_brightness max_brightness bl_power power/control; do
		if [ -f "$dev/$property" ]; then
			printf "  %s=" "$property"
			cat "$dev/$property"
		fi
	done
done

printf "\n===== SGM37604A registers, read only =====\n"
for reg in 0x10 0x11 0x19 0x1a 0x1b 0x1f; do
	value=$(sudo_run i2cget -y -f 0 0x36 "$reg" b)
	printf "%s=%s\n" "$reg" "$value"
done

printf "\n===== GPIO debug state =====\n"
sudo_run grep -E -i "PD21|PD23|sgm|backlight" /sys/kernel/debug/gpio || true

printf "\n===== PWM debug state =====\n"
sudo_run cat /sys/kernel/debug/pwm

printf "\n===== DRM connector sysfs =====\n"
for connector in /sys/class/drm/card*-*; do
	[ -f "$connector/status" ] || continue
	printf "%s status=" "$connector"
	cat "$connector/status"
	if [ -f "$connector/enabled" ]; then
		printf "  enabled="
		cat "$connector/enabled"
	fi
done

printf "\n===== live device-tree backlight properties =====\n"
sudo_run find /sys/firmware/devicetree/base -path "*/backlight@36/sgmicro,led-channels" -exec od -An -tx1 {} \;
sudo_run find /sys/firmware/devicetree/base -path "*/backlight@36/sgmicro,max-current" -exec od -An -tx1 {} \;
sudo_run find /sys/firmware/devicetree/base -path "*/backlight@36/enable-gpios" -exec od -An -tx1 {} \;

printf "\n===== complete GPIO debug state =====\n"
sudo_run cat /sys/kernel/debug/gpio

printf "\n===== PD21/PD23 pinctrl ownership =====\n"
sudo_run find /sys/kernel/debug/pinctrl -type f -name pinmux-pins -exec grep -E "pin (117|119) " {} \; || true
