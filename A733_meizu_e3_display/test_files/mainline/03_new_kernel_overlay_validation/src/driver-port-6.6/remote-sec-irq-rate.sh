set -u

irq=$(awk '$NF == "sec_ts" {gsub(":", "", $1); print $1; exit}' /proc/interrupts)
test -n "$irq"
read_count() {
  awk -v irq="${irq}:" '$1 == irq {
    total = 0;
    for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) total += $i;
    print total;
    exit
  }' /proc/interrupts
}

start=$(read_count)
start_stat=$(awk '$2 == "sec_ts" {print $14, $15; exit}' /proc/*/stat 2>/dev/null || true)
sleep 5
finish=$(read_count)
finish_stat=$(awk '$2 == "sec_ts" {print $14, $15; exit}' /proc/*/stat 2>/dev/null || true)

echo "IRQ=$irq START=$start FINISH=$finish DELTA=$((finish - start)) PER_SECOND=$(((finish - start) / 5))"
echo "THREAD_STAT_START=$start_stat"
echo "THREAD_STAT_FINISH=$finish_stat"
grep -E "^${irq}:" /proc/interrupts
ps -eLo pid,tid,psr,pcpu,stat,comm,wchan:28 --sort=-pcpu | head -n 35
dmesg --color=never | tail -n 100
