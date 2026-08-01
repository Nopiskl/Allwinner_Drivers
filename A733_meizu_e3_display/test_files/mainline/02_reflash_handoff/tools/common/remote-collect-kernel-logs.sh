#!/bin/sh
set -u

IFS= read -r sudo_password

sudo_run()
{
	printf "%s\n" "$sudo_password" | sudo -S -p "" "$@"
}

printf "\n===== reboot and shutdown history =====\n"
last -x | head -n 20

printf "\n===== pstore directory =====\n"
sudo_run ls -la /sys/fs/pstore
for file in /sys/fs/pstore/*; do
	[ -f "$file" ] || continue
	printf "\n----- %s -----\n" "$file"
	sudo_run cat "$file"
done

printf "\n===== previous boot: warning through alert =====\n"
sudo_run journalctl -b -1 -p warning..alert -o short-monotonic --no-pager

printf "\n===== previous boot: kernel tail =====\n"
sudo_run journalctl -k -b -1 -o short-monotonic --no-pager | tail -n 400

printf "\n===== previous boot: suspicious kernel messages =====\n"
sudo_run journalctl -k -b -1 -o short-monotonic --no-pager |
	grep -E -i "watchdog|hung task|blocked for|lockup|rcu|stall|panic|oops|BUG:|Call trace|drm|dsi|tcon|display|sgm37604a|sec_ts|i2c|twi|dma|irq|gpu|thermal|voltage|regulator|mmc|ext4|oom|out of memory" |
	tail -n 500

printf "\n===== current boot: display, touch, I2C and errors =====\n"
sudo_run journalctl -k -b 0 -o short-monotonic --no-pager |
	grep -E -i "watchdog|hung task|lockup|rcu|stall|panic|oops|BUG:|Call trace|drm|dsi|tcon|display|sgm37604a|sec_ts|i2c|twi|dma|irq|gpu|thermal|voltage|regulator|mmc|ext4|error|fail|timeout"
