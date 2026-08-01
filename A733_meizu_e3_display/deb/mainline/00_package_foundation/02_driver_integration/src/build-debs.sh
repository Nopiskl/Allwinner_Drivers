#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir="$script_dir/../packages"
mkdir -p "$output_dir"

build_one() {
	staging_dir=$1
	output_name=$2
	dpkg-deb --root-owner-group --build \
		"$script_dir/$staging_dir" \
		"$output_dir/$output_name"
	printf '%s\n' "$output_dir/$output_name"
}

build_one \
	meizu-e3-dkms_0.1.7_staging \
	meizu-e3-dkms_mainline-00-foundation-02-driver-integration-r1_all.deb
build_one \
	meizu-e3-dkms_0.1.8_staging \
	meizu-e3-dkms_mainline-00-foundation-02-driver-integration-r2_all.deb
