#!/bin/sh
#
# Read-only collection of the Radxa A733 state before reflashing.
# The only files created on the board are below /tmp.
#
set -eu

OUT_DIR="${1:-/tmp/radxa-a733-preflash}"
ARCHIVE="${OUT_DIR}.tar.gz"
UMASK_OLD="$(umask)"
umask 077

case "$OUT_DIR" in
    /tmp/radxa-a733-preflash-*)
        ;;
    *)
        printf 'Refusing unsafe output directory: %s\n' "$OUT_DIR" >&2
        exit 2
        ;;
esac

rm -rf -- "$OUT_DIR"
mkdir -p \
    "$OUT_DIR/boot" \
    "$OUT_DIR/config" \
    "$OUT_DIR/device-tree" \
    "$OUT_DIR/display" \
    "$OUT_DIR/logs" \
    "$OUT_DIR/packages" \
    "$OUT_DIR/storage"

run_capture() {
    destination="$1"
    shift
    (
        printf 'COMMAND:'
        printf ' %s' "$@"
        printf '\n\n'
        "$@"
        rc=$?
        printf '\nEXIT_CODE=%s\n' "$rc"
        exit "$rc"
    ) >"$OUT_DIR/$destination" 2>&1 || true
}

copy_if_present() {
    source_path="$1"
    destination_dir="$2"
    if [ -e "$source_path" ] || [ -L "$source_path" ]; then
        cp -a -- "$source_path" "$OUT_DIR/$destination_dir/"
    fi
}

{
    printf 'collection_time=%s\n' "$(date -Is)"
    printf 'hostname=%s\n' "$(hostname)"
    printf 'boot_id='
    cat /proc/sys/kernel/random/boot_id
    printf 'kernel=%s\n' "$(uname -r)"
    printf 'uid=%s\n' "$(id -u)"
    printf 'cmdline='
    cat /proc/cmdline
} >"$OUT_DIR/SNAPSHOT_INFO.txt"

run_capture system.txt sh -c '
    date -Is
    hostnamectl 2>/dev/null || true
    uname -a
    cat /etc/os-release
    uptime
    id
    printf "\n/proc/cmdline:\n"
    cat /proc/cmdline
    printf "\nboot_id:\n"
    cat /proc/sys/kernel/random/boot_id
'

run_capture boot/boot-files.txt sh -c '
    find /boot -maxdepth 3 -printf "%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p -> %l\n" 2>/dev/null | sort
'
run_capture boot/extlinux-rendered.txt sh -c '
    if [ -f /boot/extlinux/extlinux.conf ]; then
        nl -ba /boot/extlinux/extlinux.conf
    fi
'
run_capture boot/u-boot-defaults.txt sh -c '
    for f in /etc/default/u-boot /etc/u-boot-menu.conf /etc/default/flash-kernel; do
        if [ -f "$f" ]; then
            printf "\n===== %s =====\n" "$f"
            cat "$f"
        fi
    done
'
run_capture boot/u-boot-environment.txt sh -c '
    command -v fw_printenv || true
    fw_printenv 2>&1 || true
'
run_capture boot/u-boot-tools.txt sh -c '
    command -v u-boot-update || true
    dpkg-query -W -f="${binary:Package}\t${Version}\n" "u-boot*" 2>/dev/null || true
    sha256sum /usr/sbin/u-boot-update /usr/bin/u-boot-update 2>/dev/null || true
'

copy_if_present /boot/extlinux boot
copy_if_present /etc/default/u-boot config
copy_if_present /etc/u-boot-menu.conf config
copy_if_present /etc/default/flash-kernel config

mkdir -p "$OUT_DIR/boot/dtbo"
find /boot/dtbo -maxdepth 1 -type f \
    \( -name '*.dtbo' -o -name '*.disabled' -o -name '*.off' -o -name '*.dtso' \) \
    -exec cp -a -t "$OUT_DIR/boot/dtbo" -- {} + 2>/dev/null || true
run_capture boot/dtbo-inventory.txt sh -c '
    find /boot/dtbo -maxdepth 1 -type f -printf "%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %f\n" 2>/dev/null | sort
    printf "\nSHA256:\n"
    find /boot/dtbo -maxdepth 1 -type f -print0 2>/dev/null |
        sort -z |
        xargs -0 -r sha256sum
'

mkdir -p "$OUT_DIR/boot/base-dtb"
find /usr/lib /boot -type f \
    \( -name '*a733*cubie*a7a*.dtb' -o -name 'sun60i-a733-cubie-a7a.dtb' \) \
    -exec cp -a -t "$OUT_DIR/boot/base-dtb" -- {} + 2>/dev/null || true
run_capture boot/base-dtb-inventory.txt sh -c '
    find /usr/lib /boot -type f \
        \( -name "*a733*cubie*a7a*.dtb" -o -name "sun60i-a733-cubie-a7a.dtb" \) \
        -print 2>/dev/null |
        sort |
        while IFS= read -r f; do sha256sum "$f"; done
'

if [ -r /sys/firmware/fdt ]; then
    cp -- /sys/firmware/fdt "$OUT_DIR/device-tree/runtime.fdt"
fi
run_capture device-tree/runtime-model.txt sh -c '
    for f in model compatible serial-number; do
        p="/sys/firmware/devicetree/base/$f"
        if [ -r "$p" ]; then
            printf "%s=" "$f"
            tr "\000" "\n" <"$p"
        fi
    done
'
run_capture device-tree/runtime.dts sh -c '
    if command -v dtc >/dev/null 2>&1; then
        dtc -I fs -O dts /sys/firmware/devicetree/base
    fi
'
run_capture device-tree/runtime-from-fdt.dts sh -c '
    if command -v dtc >/dev/null 2>&1 && [ -r /sys/firmware/fdt ]; then
        dtc -I dtb -O dts /sys/firmware/fdt
    fi
'

run_capture packages/dpkg-manifest.txt dpkg-query -W '-f=${binary:Package}\t${Version}\t${Architecture}\n'
run_capture packages/relevant-packages.txt sh -c '
    dpkg-query -W -f="\${binary:Package}\t\${Version}\t\${Architecture}\n" \
        "linux-image*" "linux-headers*" "u-boot*" "radxa*" "meizu*" \
        "mesa*" "kwin*" "plasma*" 2>/dev/null | sort -u
'
run_capture packages/dkms-status.txt sh -c '
    dkms status 2>&1 || true
    printf "\nLoaded modules:\n"
    lsmod
    printf "\nModule metadata:\n"
    for m in sec_ts sgm37604a; do
        modinfo "$m" 2>&1 || true
    done
'
run_capture packages/apt-sources.txt sh -c '
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
        if [ -f "$f" ]; then
            printf "\n===== %s =====\n" "$f"
            cat "$f"
        fi
    done
'

for path in \
    /usr/src/meizu-e3-dkms-* \
    /usr/lib/meizu-e3-dkms \
    /etc/xdg/autostart/meizu-e3-touch-map.desktop \
    /etc/modules-load.d \
    /etc/modprobe.d; do
    for expanded in $path; do
        if [ -e "$expanded" ]; then
            cp -a --parents -- "$expanded" "$OUT_DIR/config/" 2>/dev/null || true
        fi
    done
done

run_capture storage/lsblk.txt lsblk -a -o NAME,PATH,TYPE,SIZE,LOG-SEC,PHY-SEC,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS
run_capture storage/findmnt.txt findmnt -A
run_capture storage/blkid.txt blkid
run_capture storage/partitions.txt sh -c '
    cat /proc/partitions
    printf "\nEFI variables:\n"
    efibootmgr -v 2>&1 || true
'

run_capture logs/dmesg.txt dmesg -T
run_capture logs/journal-current.txt timeout 60s journalctl --no-pager -b -o short-monotonic
run_capture logs/journal-previous.txt timeout 60s journalctl --no-pager -b -1 -o short-monotonic
run_capture logs/journal-boots.txt journalctl --list-boots --no-pager
run_capture logs/kernel-fault-summary.txt sh -c '
    for boot in -1 0; do
        printf "\n===== journalctl -k -b %s =====\n" "$boot"
        journalctl --no-pager -k -b "$boot" 2>/dev/null |
            grep -E -i "sunxi_de_atomic_flush|PageTable Invalid|not mapped|Bug is in DE|rcu.*stall|NULL pointer|Unable to handle|watchdog|soft lockup|hard LOCKUP|Call trace|panic|drm|dsi|tcon|combo.?phy|iommu" || true
    done
'
run_capture logs/services.txt sh -c '
    systemctl --no-pager --full status display-manager.service 2>&1 || true
    systemctl --no-pager --full status systemd-networkd.service NetworkManager.service 2>&1 || true
    systemctl --failed --no-pager --full 2>&1 || true
    loginctl list-sessions --no-legend 2>&1 || true
'

run_capture display/drm-state.txt sh -c '
    for f in /sys/kernel/debug/dri/*/state; do
        if [ -r "$f" ]; then
            printf "\n===== %s =====\n" "$f"
            cat "$f"
        fi
    done
'
run_capture display/drm-sysfs.txt sh -c '
    find /sys/class/drm -maxdepth 2 \
        \( -name status -o -name enabled -o -name modes -o -name mode -o -name dpms \) \
        -type f -print 2>/dev/null |
        sort |
        while IFS= read -r f; do
            printf "\n===== %s =====\n" "$f"
            cat "$f"
        done
'
run_capture display/backlight.txt sh -c '
    find /sys/class/backlight -maxdepth 2 -type f -print 2>/dev/null |
        sort |
        while IFS= read -r f; do
            case "$f" in
                */brightness|*/actual_brightness|*/max_brightness|*/bl_power|*/type|*/scale)
                    printf "%s=" "$f"
                    cat "$f"
                    ;;
            esac
        done
'
run_capture display/input.txt sh -c '
    cat /proc/bus/input/devices
    printf "\n/sys/class/input:\n"
    find /sys/class/input -maxdepth 2 -type l -printf "%p -> %l\n" 2>/dev/null | sort
'
run_capture display/i2c-devices.txt sh -c '
    find /sys/bus/i2c/devices -maxdepth 2 \
        \( -name name -o -name modalias -o -name status -o -name driver \) \
        -print 2>/dev/null |
        sort |
        while IFS= read -r f; do
            if [ -f "$f" ] && [ -r "$f" ]; then
                printf "%s=" "$f"
                cat "$f"
            elif [ -L "$f" ]; then
                printf "%s -> %s\n" "$f" "$(readlink "$f")"
            fi
        done
'
run_capture display/interrupts.txt cat /proc/interrupts
run_capture display/graphics-sessions.txt sh -c '
    for home in /home/* /root; do
        for f in \
            "$home/.config/kwinoutputconfig.json" \
            "$home/.local/share/kscreen/"* \
            "$home/.config/monitors.xml"; do
            if [ -f "$f" ]; then
                printf "\n===== %s =====\n" "$f"
                cat "$f"
            fi
        done
    done
    for f in /etc/X11/xorg.conf /etc/X11/xorg.conf.d/* /etc/sddm.conf /etc/sddm.conf.d/*; do
        if [ -f "$f" ]; then
            printf "\n===== %s =====\n" "$f"
            cat "$f"
        fi
    done
'

run_capture config/rsetup-files.txt sh -c '
    find /etc /var/lib -maxdepth 4 \
        \( -iname "*rsetup*" -o -iname "*overlay*" -o -iname "*u-boot*" \) \
        -printf "%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p -> %l\n" 2>/dev/null |
        sort
'
run_capture config/sysctl-and-cmdline.txt sh -c '
    sysctl kernel.sysrq kernel.watchdog kernel.nmi_watchdog 2>&1 || true
    for f in /etc/sysctl.conf /etc/sysctl.d/* /etc/default/grub; do
        if [ -f "$f" ]; then
            printf "\n===== %s =====\n" "$f"
            cat "$f"
        fi
    done
'

find "$OUT_DIR" -type f -print0 |
    sort -z |
    xargs -0 sha256sum >"$OUT_DIR/SHA256SUMS"

rm -f -- "$ARCHIVE"
tar -C "$(dirname "$OUT_DIR")" -czf "$ARCHIVE" "$(basename "$OUT_DIR")"
chmod 0644 "$ARCHIVE"
umask "$UMASK_OLD"

printf 'ARCHIVE=%s\n' "$ARCHIVE"
printf 'ARCHIVE_SHA256='
sha256sum "$ARCHIVE" | awk '{print $1}'
printf 'ARCHIVE_SIZE='
stat -c '%s' "$ARCHIVE"
