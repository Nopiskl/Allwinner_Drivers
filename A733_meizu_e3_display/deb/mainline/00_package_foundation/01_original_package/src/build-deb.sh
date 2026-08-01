#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root="$script_dir/meizu-e3-dkms_0.1.6_all.unpacked"
output_dir="$script_dir/../packages"
output_file="$output_dir/meizu-e3-dkms_mainline-00-foundation-01-original_all.deb"
build_root=$(mktemp -d)

cleanup() {
	rm -rf -- "$build_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$build_root/DEBIAN" "$output_dir"
cp -a "$source_root/data/." "$build_root/"
cp -a "$source_root/control/." "$build_root/DEBIAN/"
dpkg-deb --root-owner-group --build "$build_root" "$output_file"
printf '%s\n' "$output_file"
