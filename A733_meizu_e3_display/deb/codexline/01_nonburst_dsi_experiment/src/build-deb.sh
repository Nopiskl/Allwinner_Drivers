#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
staging_dir="$script_dir/meizu-e3-dkms_0.1.10_staging"
output_dir="$script_dir/../packages"
output_file="$output_dir/meizu-e3-dkms_codexline-01-nonburst-dsi-experiment_all.deb"

mkdir -p "$output_dir"
dpkg-deb --root-owner-group --build "$staging_dir" "$output_file"
printf '%s\n' "$output_file"
