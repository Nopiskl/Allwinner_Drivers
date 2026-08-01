set -euxo pipefail

build_root=/tmp/meizu-e3-driver-build
source_dir="$build_root/meizu-e3-drivers-t4-0.1.10"

case "$build_root" in
  /tmp/meizu-e3-driver-build) ;;
  *) echo 'refusing unsafe build path' >&2; exit 2 ;;
esac
rm -rf -- "$build_root"
mkdir -p "$source_dir"
tar -xzf /tmp/meizu-e3-drivers-t4-0.1.10.tar.gz -C "$source_dir"

echo '=== toolchain ==='
uname -a
command -v make
command -v gcc
test -e "/lib/modules/$(uname -r)/build/Makefile"
sha256sum /tmp/meizu-e3-drivers-t4-0.1.10.tar.gz \
  "$source_dir/drivers/sec_ts/sec_ts_main.c" \
  "$source_dir/drivers/backlight/sgm37604a.c"

echo '=== build ==='
make -C "$source_dir" KERNELRELEASE="$(uname -r)" all

echo '=== module ABI/metadata ==='
for module in \
  "$source_dir/drivers/sec_ts/sec_ts.ko" \
  "$source_dir/drivers/backlight/sgm37604a.ko"; do
  test -s "$module"
  sha256sum "$module"
  /sbin/modinfo "$module" | grep -E '^(filename|license|description|alias|depends|name|vermagic):'
done
