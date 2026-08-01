#!/bin/sh
set -eu

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT HUP INT TERM
journalctl -b 0 -k --no-pager -q -o short-monotonic >"$log_file"

printf 'flush='
grep -c 'sunxi_de_atomic_flush timeout' "$log_file" || true
printf 'page_table='
grep -c 'PageTable Invalid' "$log_file" || true
printf 'de_fault='
grep -c 'Bug is in DE' "$log_file" || true
printf 'touch_unknown='
grep -E -i -c 'sec_ts.*unknown event' "$log_file" || true

echo "=== last display fault ==="
grep -E \
	'sunxi_de_atomic_flush timeout|PageTable Invalid|Bug is in DE' \
	"$log_file" |
	tail -n 5 ||
	true
