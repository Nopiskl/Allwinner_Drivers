set -euxo pipefail

package=meizu-e3-drivers-t4
version=0.1.10
kernel=6.6.98-3-aw2511
source_dir="/usr/src/${package}-${version}"
state_dir=/var/lib/meizu-e3-drivers-t4/20260731-t4-v001-reg1
archive=/tmp/meizu-e3-drivers-t4-0.1.10.tar.gz
expected_archive=e8d8a13917b2216821c81ab806d844120af9b5355b9f67b805af5c15b4de9441

test "$(uname -r)" = "$kernel"
test "$(cat /proc/sys/kernel/random/boot_id)" = \
  7a8fe62e-d15a-4392-ad59-a74c783e215a
test "$(sha256sum "$archive" | awk '{print $1}')" = "$expected_archive"
test -x /usr/sbin/dkms
test ! -e "$source_dir"

for dev_compat in '0-0036:sgmicro,sgm37604a' '0-0048:sec,sec_ts'; do
  dev=${dev_compat%%:*}
  expected=${dev_compat#*:}
  actual=$(tr '\0' '\n' < "/sys/bus/i2c/devices/$dev/of_node/compatible" | head -n 1)
  test "$actual" = "$expected"
done

install -d -m 0755 "$state_dir/preinstall" "$source_dir"
cp -a /boot/extlinux/extlinux.conf "$state_dir/preinstall/extlinux.conf"
cp -a /boot/dtbo/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo \
  "$state_dir/preinstall/"
sha256sum /boot/extlinux/extlinux.conf \
  /boot/dtbo/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo \
  > "$state_dir/preinstall/boot-sha256.txt"

rollback_install() {
  set +e
  /usr/sbin/dkms remove -m "$package" -v "$version" --all
  rm -f -- \
    /etc/modules-load.d/meizu-e3-drivers.conf \
    /etc/xdg/autostart/meizu-e3-map-touch.desktop \
    /etc/sddm.conf.d/90-meizu-e3-map-touch.conf \
    /usr/local/libexec/meizu-e3-map-touch-once
  case "$source_dir" in
    /usr/src/meizu-e3-drivers-t4-0.1.10) rm -rf -- "$source_dir" ;;
  esac
}
trap rollback_install ERR

tar -xzf "$archive" -C "$source_dir"
chown -R root:root "$source_dir"
sha256sum \
  "$source_dir/drivers/sec_ts/sec_ts_main.c" \
  "$source_dir/drivers/backlight/sgm37604a.c" \
  > "$state_dir/installed-source-sha256.txt"

/usr/sbin/dkms add -m "$package" -v "$version"
/usr/sbin/dkms build -m "$package" -v "$version" -k "$kernel"
/usr/sbin/dkms install -m "$package" -v "$version" -k "$kernel"

install -d -m 0755 /usr/local/libexec /etc/sddm.conf.d
install -m 0755 /tmp/meizu-e3-map-touch-once \
  /usr/local/libexec/meizu-e3-map-touch-once
install -m 0644 /tmp/meizu-e3-map-touch.desktop \
  /etc/xdg/autostart/meizu-e3-map-touch.desktop
install -m 0644 /tmp/90-meizu-e3-map-touch.conf \
  /etc/sddm.conf.d/90-meizu-e3-map-touch.conf
install -m 0644 /tmp/meizu-e3-drivers.conf \
  /etc/modules-load.d/meizu-e3-drivers.conf

/sbin/depmod -a "$kernel"

# This installation is not allowed to alter the active boot configuration.
sha256sum -c "$state_dir/preinstall/boot-sha256.txt"

echo '=== DKMS status ==='
/usr/sbin/dkms status -m "$package" -v "$version"
echo '=== installed modules ==='
for module in sec_ts sgm37604a; do
  path=$(/sbin/modinfo -n "$module")
  sha256sum "$path"
  /sbin/modinfo "$module" | grep -E '^(filename|description|alias|name|vermagic):'
done
echo '=== persistent configuration ==='
ls -l \
  /etc/modules-load.d/meizu-e3-drivers.conf \
  /usr/local/libexec/meizu-e3-map-touch-once \
  /etc/xdg/autostart/meizu-e3-map-touch.desktop \
  /etc/sddm.conf.d/90-meizu-e3-map-touch.conf

trap - ERR
echo 'INSTALL_COMPLETE_NO_MODULES_LOADED'
