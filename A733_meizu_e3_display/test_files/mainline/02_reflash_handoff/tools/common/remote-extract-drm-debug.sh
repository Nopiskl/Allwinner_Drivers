#!/bin/sh
set -eu

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT HUP INT TERM

journalctl -b 0 -k --no-pager -q -o short-monotonic >"$log_file"

echo "=== DRM DEBUG DUMP FROM FIRST MARKER ==="
awk '
	/--- SUNXI DRM DEBUG ---/ {printing = 1}
	printing {print}
' "$log_file" | head -n 520

echo "=== ADDRESS AND MAP REFERENCES ==="
grep -E -i \
	'fa000000|fc000000|dma_addr|unmap-ts|map:' \
	"$log_file" ||
	true
