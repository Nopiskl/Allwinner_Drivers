set -u

event=/dev/input/event20
test -c "$event"
echo '=== GPIO debug ==='
grep -E -i 'PD18|gpio-114|gpio-.*sec|sec_ts|GPIO.*82' /sys/kernel/debug/gpio || true
echo '=== pinctrl PD18 references ==='
grep -Rsn -E 'PD18|pin 114|gpio-114|sec_ts' /sys/kernel/debug/pinctrl 2>/dev/null | head -n 120 || true
echo '=== 2-second evtest sample ==='
if command -v evtest >/dev/null 2>&1; then
  timeout 2 evtest "$event" 2>&1 | head -n 240 || true
else
  echo 'evtest not installed'
fi
echo '=== IRQ rate over the same 2 seconds ==='
irq=$(awk '$NF == "sec_ts" {gsub(":", "", $1); print $1; exit}' /proc/interrupts)
read_count() {
  awk -v irq="${irq}:" '$1 == irq {
    total = 0;
    for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) total += $i;
    print total;
    exit
  }' /proc/interrupts
}
start=$(read_count)
sleep 2
finish=$(read_count)
echo "IRQ=$irq START=$start FINISH=$finish DELTA=$((finish - start)) PER_SECOND=$(((finish - start) / 2))"
ps -eLo pid,tid,psr,pcpu,stat,comm,wchan:28 --sort=-pcpu | head -n 16
