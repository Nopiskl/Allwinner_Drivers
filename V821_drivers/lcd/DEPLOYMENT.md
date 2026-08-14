# ST7789V 正式版制品、ADB 部署、烧写与回退

本文接续 [`porting/PORTING_AND_BUILD.md`](porting/PORTING_AND_BUILD.md)：前一篇负责“源码如何移植、如何编译”，本文负责“如何把已验收输出组成正式包、如何通过 ADB 在设备上备份 boot、烧写、加载 KO、运行 LVGL，以及如何回退”。

本文只使用唯一正式包：

```text
V821_drivers/lcd/artifacts/st7789v_240x280/
```

不要建立带日期、`r1/r2/r3` 或 offset 名称的第二个正式包。实验 KO 放到设备 SD 卡的独立实验目录，按 [`MANUAL_TEST.md`](MANUAL_TEST.md) 验收；只有通过后才更新此正式目录。

## 1. 正式包内容及来源

目录结构：

```text
V821_drivers/lcd/artifacts/st7789v_240x280/
├── 00_preflight.sh
├── 01_backup_boot.sh
├── 10_load_lcd.sh
├── 11_run_lvgl.sh
├── 12_unload_lcd.sh
├── README.md
├── SHA256SUMS
├── backup/
│   ├── boot_mtd4_19700101_012242.img
│   └── boot_mtd4_19700101_012242.img.sha256
├── boot/
│   ├── boot.img
│   └── sunxi.dtb
├── modules/
│   ├── cfbcopyarea.ko
│   ├── cfbfillrect.ko
│   ├── cfbimgblt.ko
│   ├── fb_sys_fops.ko
│   ├── lcd_fb.ko
│   └── lcd_fb_spi_panel.ko
└── userspace/
    ├── lv_examples
    └── lv_examples_8.3.2-1_riscv32_a27l2_rv32imac_zicsr_zifencei.ipk
```

### 1.1 从 SDK 构建输出收集 KO

内核构建完成后，从同一轮 `5.4.220` staging 目录收集模块：

```sh
export V821_DRIVERS_ROOT=/path/to/Allwinner_Drivers/V821_drivers
export LCD_SDK_ROOT=/path/to/tina-v821-v1.3
export LCD_BUNDLE="$V821_DRIVERS_ROOT/lcd/artifacts/st7789v_240x280"
export LCD_KO_OUT="$LCD_SDK_ROOT/out/v821/kernel/staging/lib/modules/5.4.220"

mkdir -p "$LCD_BUNDLE/modules"
install -m 0644 "$LCD_KO_OUT/cfbcopyarea.ko" "$LCD_BUNDLE/modules/"
install -m 0644 "$LCD_KO_OUT/cfbfillrect.ko" "$LCD_BUNDLE/modules/"
install -m 0644 "$LCD_KO_OUT/cfbimgblt.ko" "$LCD_BUNDLE/modules/"
install -m 0644 "$LCD_KO_OUT/fb_sys_fops.ko" "$LCD_BUNDLE/modules/"
install -m 0644 "$LCD_KO_OUT/lcd_fb_spi_panel.ko" "$LCD_BUNDLE/modules/"
install -m 0644 "$LCD_KO_OUT/lcd_fb.ko" "$LCD_BUNDLE/modules/"
```

当前加载所需的最小集合是：

```text
fb_sys_fops.ko -> lcd_fb_spi_panel.ko -> lcd_fb.ko
```

三个 `cfb*.ko` 是 `CONFIG_LCD_FB` 所选择的同批 framebuffer helper 产物，正式包保留它们以便在其他启动配置下补齐依赖；当前设备不需要由加载脚本主动 `insmod`。

严禁混用不同轮次或不同 kernel release 的 KO。收集后检查：

```sh
modinfo "$LCD_BUNDLE/modules/lcd_fb.ko" | \
  rg '^(version|srcversion|depends|vermagic):'
sha256sum "$LCD_BUNDLE/modules/"*.ko
```

正式 `lcd_fb.ko` 必须是：

```text
version:    1.0.7
srcversion: 67770EC052084657BDF7FE4
depends:    fb_sys_fops
vermagic:   5.4.220 preempt mod_unload riscv
sha256:     d487d338a2210e9226ff7651f333d70e49b3159418fcbc6d2e27f1e0a4df25e2
```

### 1.2 收集 LVGL 二进制和 IPK

```sh
export LCD_LV_BUILD="$LCD_SDK_ROOT/out/v821/avaota_f1/openwrt/build_dir/target/lv_examples/ipkg-riscv32_a27l2_rv32imac_zicsr_zifencei/lv_examples/usr/bin/lv_examples"
export LCD_LV_IPK="$LCD_SDK_ROOT/out/v821/avaota_f1/openwrt/extra/packages/riscv32_a27l2_rv32imac_zicsr_zifencei/base/lv_examples_8.3.2-1_riscv32_a27l2_rv32imac_zicsr_zifencei.ipk"

mkdir -p "$LCD_BUNDLE/userspace"
install -m 0755 "$LCD_LV_BUILD" "$LCD_BUNDLE/userspace/lv_examples"
install -m 0644 "$LCD_LV_IPK" "$LCD_BUNDLE/userspace/"

file "$LCD_BUNDLE/userspace/lv_examples"
sha256sum "$LCD_BUNDLE/userspace/"*
```

这里复制 `ipkg-.../usr/bin/lv_examples` 中已经 strip 的安装版本，不复制 `.pkgdir` 中较大的中间文件。正式值：

```text
lv_examples size:   1303036
lv_examples sha256: 63f117b3a019f77dac0c15f9b0ca1ced52ddefe96fda2e7208dcd40b443c2752
IPK size:           490621
IPK sha256:         abdbfb9b7eca4623af4e0d54e8094409ca423f33774110de7dcf46f06aa5759c
```

设备部署使用独立 `lv_examples` 即可，IPK 只是保留标准 OpenWrt 包形式；无需同时安装 IPK。

### 1.3 收集 boot.img 和 DTB

正常构建输出位置：

```text
out/v821/avaota_f1/openwrt/boot.img
out/v821/avaota_f1/openwrt/sunxi.dtb
```

仅当候选 boot 已完成“备份 -> 烧写 -> 回读 -> 重启 -> 模块/LVGL/实物”整套验证后，才能收录：

```sh
mkdir -p "$LCD_BUNDLE/boot"
install -m 0644 /path/to/validated/boot.img "$LCD_BUNDLE/boot/boot.img"
install -m 0644 /path/to/matching/sunxi.dtb "$LCD_BUNDLE/boot/sunxi.dtb"
```

本次正式包是已经上板验证的一批：

```text
boot/boot.img
  size:   2314240
  sha256: 7791017db6ea3959cf1d2f37575d0693a7b10bc94ee7e0d151c4b93aaef105bc

boot/sunxi.dtb
  size:   63394
  sha256: f17401dbe4ef96b5dd599a52741b38391099093846d330d8d4192a568e30f131
```

当前 SDK 后续重新构建的 `out/.../boot.img` 哈希可能与正式值不同。未经再次上板验证，不要用当前输出机械覆盖 `boot/boot.img`。

### 1.4 生成固定文件清单

`backup/` 是每台设备动态产生的恢复材料，不计入固定发布清单。所有其他固定文件用以下方式重建 `SHA256SUMS`：

```sh
cd "$LCD_BUNDLE"
find . -type f \
  ! -path './backup/*' \
  ! -name SHA256SUMS \
  -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
sha256sum -c SHA256SUMS
```

如果修改 README 或脚本，必须重新生成清单；不要手工伪造旧哈希。

## 2. 主机端部署准备

从 SDK 根目录设置变量。序列号以 `adb devices -l` 的实际输出为准：

```sh
export V821_DRIVERS_ROOT=/path/to/Allwinner_Drivers/V821_drivers
export LCD_SDK_ROOT=/path/to/tina-v821-v1.3
export LCD_BUNDLE="$V821_DRIVERS_ROOT/lcd/artifacts/st7789v_240x280"

adb devices -l
export LCD_ADB_SERIAL=YOUR_ADB_SERIAL
adb -s "$LCD_ADB_SERIAL" get-state
```

先在主机端验证固定制品、原始 boot 备份和脚本语法：

```sh
cd "$LCD_BUNDLE"
sha256sum -c SHA256SUMS
(
  cd backup
  sha256sum -c boot_mtd4_19700101_012242.img.sha256
)
for SCRIPT in ./*.sh; do
  sh -n "$SCRIPT"
done
```

任何固定文件校验失败都应停止。不要加载模块或写 NOR。

确认设备端 ADB Shell 有 root 权限，并且 SD 卡已挂载、可写且空间足够：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
test "$(id -u)" = 0
test -d /mnt/extsd
test -w /mnt/extsd
uname -a
df -h /mnt/extsd
cat /proc/mtd
'
```

模块加载和 MTD 写入都需要 uid 0。若 `id -u` 不是 `0`，应先使用已有的可 root 调试固件；本文不通过绕过权限继续操作。

## 3. 上传正式包到 SD 卡

本项目把大文件放在 `/mnt/extsd`，避免占用 rootfs：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'mkdir -p /mnt/extsd/st7789v_240x280'

adb -s "$LCD_ADB_SERIAL" push \
  "$LCD_BUNDLE/." \
  /mnt/extsd/st7789v_240x280/
```

在设备端再次核对传输后的固定文件：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'cd /mnt/extsd/st7789v_240x280 && sha256sum -c SHA256SUMS'
```

`adb push` 会覆盖同名固定文件，但不会自动删除设备目录中的旧实验文件；正式脚本只引用固定子目录，不会加载旁边的候选文件。需要清理旧实验目录时，应明确指定那个实验目录，不要递归删除 `/mnt/extsd`。

运行只读预检：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/00_preflight.sh'
```

该脚本只读取运行内核、MTD、DT 和文件哈希，不写 NOR，也不加载模块。首次更新前，SPI1/lcd_fb 的运行 DT 可能仍不是 `okay`，这是下一节需要更新 boot 的判断依据。

## 4. 判断是否需要刷 boot

只修改以下内容时不刷 boot：

- `st7789v_240x280.c` 的初始化序列、offset、MADCTL、gamma、延时。
- 编入 `lcd_fb.ko` 的框架逻辑。
- LVGL 或 sunxifb 用户态代码。

以下内容变更才需要刷 boot：

- `board.dts` 的 SPI1、DCX、RESET、lcd_fb endpoint、分辨率/格式/帧率。
- 内建的 SPI NG/DBI 驱动或其他 boot 内核内容。
- 设备当前运行 DT 尚未启用 SPI1/lcd_fb。

设备当前 DT 的只读检查：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
for NODE in \
  /proc/device-tree/soc@2002000/spi@44026000/status \
  /proc/device-tree/soc@2002000/lcd_fb/status \
  /proc/device-tree/soc@2002000/spi@44026000/slave@0/lcd_driver_name
do
  printf "%s: " "$NODE"
  if test -r "$NODE"; then tr -d "\000" < "$NODE"; else printf missing; fi
  printf "\n"
done
'
```

已更新设备的预期值依次为 `okay`、`okay`、`st7789v_240x280`。三项都正确时，日常测试直接跳到第 8 节加载 KO。

## 5. 确认 boot 分区位置

烧写前每次都重新识别，不依赖“上次是 mtd4”的记忆：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
cat /proc/mtd
printf "name: "; cat /sys/class/mtd/mtd4/name
printf "size: "; cat /sys/class/mtd/mtd4/size
printf "erasesize: "; cat /sys/class/mtd/mtd4/erasesize
ls -l /dev/mtd4 /dev/mtdblock4
grep "^mtd4: 00500000 00010000 \"boot\"$" /proc/mtd
'
```

本机实测映射：

```text
mtd4: 00500000 00010000 "boot"
```

含义是：boot 分区恰好 5 MiB，erase block 为 64 KiB，同时存在只读/回读使用的 `/dev/mtd4` 和经过 MTD block 层写入的 `/dev/mtdblock4`。如果编号、名称、大小或 erase size 任一不一致，立即停止，不能把本文的 `mtd4` 命令用于该设备。

## 6. 烧写前完整备份 boot

运行包内只读备份脚本：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/01_backup_boot.sh'
```

脚本实际执行的关键动作是：

```sh
dd if=/dev/mtd4 of="$BACKUP" bs=65536 count=80
```

即完整读取 `80 × 64 KiB = 5,242,880 bytes`，随后在 `backup/` 中生成同名 `.sha256`。文件名时间来自设备时钟；项目最早备份中的 `19700101` 仅表示设备 RTC 未校时，不影响内容。

列出刚生成的备份并在设备端校验：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
cd /mnt/extsd/st7789v_240x280/backup
ls -lh boot_mtd4_*.img boot_mtd4_*.img.sha256
for SUM in boot_mtd4_*.img.sha256; do sha256sum -c "$SUM"; done
'
```

再拉回主机，保证 SD 卡和主机各保留一份：

```sh
mkdir -p "$LCD_BUNDLE/backup"
adb -s "$LCD_ADB_SERIAL" pull \
  /mnt/extsd/st7789v_240x280/backup/. \
  "$LCD_BUNDLE/backup/"
```

项目开始前原始 boot 备份是：

```text
V821_drivers/lcd/artifacts/st7789v_240x280/backup/boot_mtd4_19700101_012242.img
size:   5242880
sha256: a29131e949663f617029f31b6e3e86419ceb46ce6b6dfd4c55f7ed52f6328e81
```

只有备份尺寸和哈希均正确，且已经拉回主机，才进入烧写步骤。

## 7. 烧写已验收 boot.img

这是本文唯一修改 SPI-NOR 的步骤。需要保证供电稳定、ADB 稳定，并且已有可用的 FEL/PhoenixSuit 离线恢复手段。所有校验通过后再执行。

先只读确认镜像：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
IMAGE=/mnt/extsd/st7789v_240x280/boot/boot.img
EXPECTED=7791017db6ea3959cf1d2f37575d0693a7b10bc94ee7e0d151c4b93aaef105bc
grep -q "^mtd4: 00500000 00010000 \"boot\"$" /proc/mtd
test "$(wc -c < "$IMAGE" | tr -d " ")" = 2314240
echo "$EXPECTED  $IMAGE" | sha256sum -c -
echo "boot image and target checks passed"
'
```

2,314,240 bytes 恰好是 4,520 个 512-byte sector。只向精确目标写这个长度，并立即回读相同长度：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
IMAGE=/mnt/extsd/st7789v_240x280/boot/boot.img
READBACK=/mnt/extsd/st7789v_240x280/backup/boot_after_write_2314240.img
EXPECTED=7791017db6ea3959cf1d2f37575d0693a7b10bc94ee7e0d151c4b93aaef105bc

grep -q "^mtd4: 00500000 00010000 \"boot\"$" /proc/mtd
test "$(wc -c < "$IMAGE" | tr -d " ")" = 2314240
echo "$EXPECTED  $IMAGE" | sha256sum -c -

dd if="$IMAGE" of=/dev/mtdblock4 bs=512 count=4520 conv=fsync
sync
dd if=/dev/mtd4 of="$READBACK" bs=512 count=4520
test "$(wc -c < "$READBACK" | tr -d " ")" = 2314240
echo "$EXPECTED  $READBACK" | sha256sum -c -
echo "boot write/readback verification passed"
'
```

回读哈希不一致时禁止重启，应保持 ADB 在线并立即按第 11 节使用完整备份恢复。只有出现 `boot write/readback verification passed` 后才重启：

```sh
adb -s "$LCD_ADB_SERIAL" reboot
adb -s "$LCD_ADB_SERIAL" wait-for-device
adb -s "$LCD_ADB_SERIAL" shell 'uname -a; cat /proc/mtd'
```

重启后再次执行 DT 检查和预检：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/00_preflight.sh'
```

## 8. 加载正式 KO

确保 LVGL 没有占用 framebuffer，然后运行正式脚本：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
PIDS=$(pidof lv_examples 2>/dev/null || true)
test -z "$PIDS" || kill $PIDS
'

adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/10_load_lcd.sh'
```

`10_load_lcd.sh` 会自动完成和检查：

1. 运行内核必须为 5.4.220。
2. SPI1 和 lcd_fb 的运行 DT 必须为 `okay`。
3. `lcd_fb.ko` 哈希必须等于正式值。
4. 已加载其他版本时，先停止 LVGL，再替换 lcd_fb。
5. 按 `fb_sys_fops -> lcd_fb_spi_panel -> lcd_fb` 加载。
6. 根据 sysfs 找到 lcd_fb 对应的 `/dev/fbN`。
7. framebuffer 必须为 `240,560`、16 bpp。
8. `srcversion` 必须为正式值，`spi_speed_hz` 必须为 `0`，即使用 DTS 的 48 MHz。

加载后人工复核：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
cat /proc/modules | grep -E "^(lcd_fb|lcd_fb_spi_panel|fb_sys_fops) "
cat /sys/module/lcd_fb/srcversion
cat /sys/module/lcd_fb/parameters/spi_speed_hz
dmesg | tail -n 150
'
```

日志应包含 `vendor-seq-20260814-r4-y0-nl280` 的 init start/complete，不应出现 SPI timeout、transfer error、DMA error 或 oops。

## 9. 色条和 LVGL 验收

先显示 lcd_fb 自带色条：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
echo 0 > /sys/class/lcd_fb/lcd_fb/attr/screenid
echo 1 > /sys/class/lcd_fb/lcd_fb/attr/colorbar
'
```

检查颜色、方向、左右边缘、顶部和底部 280 行是否全部覆盖。再在一个终端以前台方式运行 LVGL music demo：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/11_run_lvgl.sh 1'
```

脚本不会固定使用 `/dev/fb1`，而是查找 lcd_fb 并设置：

```text
LV_SUNXIFB_DEVICE=/dev/fbN
```

因此 DISP2 保留 `/dev/fb0` 时也不会误选。触摸未适配，evdev 相关警告可忽略；本轮验收项目是显示。

结束 LVGL：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
PIDS=$(pidof lv_examples 2>/dev/null || true)
test -z "$PIDS" || kill $PIDS
'
```

## 10. 卸载和重新加载

先确保 `lv_examples` 已停止：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/12_unload_lcd.sh'
```

卸载顺序是 `lcd_fb -> lcd_fb_spi_panel -> fb_sys_fops`。重新加载：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/10_load_lcd.sh'
```

正常的模块重载不需要重启或重刷 boot。

## 11. 回退

### 11.1 从实验 KO 恢复正式 KO

```sh
adb -s "$LCD_ADB_SERIAL" shell '
PIDS=$(pidof lv_examples 2>/dev/null || true)
test -z "$PIDS" || kill $PIDS
sh /mnt/extsd/st7789v_240x280/12_unload_lcd.sh
sh /mnt/extsd/st7789v_240x280/10_load_lcd.sh
'
```

正式脚本会重新锁定哈希、srcversion 和 `spi_speed_hz=0`。

### 11.2 恢复项目开始前的完整 boot

先在主机验证原始备份，再推送到 SD 卡的明确路径：

```sh
export LCD_ORIGINAL_BOOT="$LCD_BUNDLE/backup/boot_mtd4_19700101_012242.img"
test "$(stat -c %s "$LCD_ORIGINAL_BOOT")" = 5242880
test "$(sha256sum "$LCD_ORIGINAL_BOOT" | awk '{print $1}')" = \
  a29131e949663f617029f31b6e3e86419ceb46ce6b6dfd4c55f7ed52f6328e81

adb -s "$LCD_ADB_SERIAL" push "$LCD_ORIGINAL_BOOT" \
  /mnt/extsd/st7789v_240x280/backup/original_boot_to_restore.img
```

设备端再次检查目标、大小和哈希。确认无误后写满全部 80 个 erase block，并全量回读校验：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
IMAGE=/mnt/extsd/st7789v_240x280/backup/original_boot_to_restore.img
READBACK=/mnt/extsd/st7789v_240x280/backup/original_boot_restore_readback.img
EXPECTED=a29131e949663f617029f31b6e3e86419ceb46ce6b6dfd4c55f7ed52f6328e81

grep -q "^mtd4: 00500000 00010000 \"boot\"$" /proc/mtd
test "$(wc -c < "$IMAGE" | tr -d " ")" = 5242880
echo "$EXPECTED  $IMAGE" | sha256sum -c -

dd if="$IMAGE" of=/dev/mtdblock4 bs=65536 count=80 conv=fsync
sync
dd if=/dev/mtd4 of="$READBACK" bs=65536 count=80
echo "$EXPECTED  $READBACK" | sha256sum -c -
echo "original boot restore/readback verification passed"
'
```

仅在全量回读一致后重启：

```sh
adb -s "$LCD_ADB_SERIAL" reboot
adb -s "$LCD_ADB_SERIAL" wait-for-device
```

原 boot 会把 SPI1/lcd_fb 恢复到项目开始前的 DT/内核状态，正式 KO 因 DT 不再启用而不能直接加载，这是预期回退结果。

### 11.3 设备无法进入 ADB

此时用户态备份/恢复命令不可用。使用已经准备好的全志 FEL/PhoenixSuit 恢复流程和已知可启动固件；不要继续尝试对未知 MTD 节点写入。

## 12. 日志采集和最终 Checklist

失败时在设备端保存：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
LOG_DIR=/mnt/extsd/st7789v_240x280/logs
mkdir -p "$LOG_DIR"
dmesg > "$LOG_DIR/dmesg.txt"
cat /proc/modules > "$LOG_DIR/modules.txt"
cat /proc/interrupts > "$LOG_DIR/interrupts.txt"
cat /proc/mtd > "$LOG_DIR/mtd.txt"
for FB_SYS in /sys/class/graphics/fb*; do
  test -e "$FB_SYS" || continue
  NAME=${FB_SYS##*/}
  {
    readlink "$FB_SYS" || true
    cat "$FB_SYS/name" 2>/dev/null || true
    cat "$FB_SYS/virtual_size" 2>/dev/null || true
    cat "$FB_SYS/bits_per_pixel" 2>/dev/null || true
  } > "$LOG_DIR/$NAME.txt"
done
sync
'

adb -s "$LCD_ADB_SERIAL" pull \
  /mnt/extsd/st7789v_240x280/logs \
  "$V821_DRIVERS_ROOT/lcd/device_logs/"
```

最终人工确认：

- [ ] `V821_drivers/lcd/artifacts` 顶层只有 `st7789v_240x280/` 一个正式结果。
- [ ] 主机和设备端 `sha256sum -c SHA256SUMS` 全部通过。
- [ ] boot 分区每次都由 `/proc/mtd` 确认，不靠固定编号猜测。
- [ ] 写 boot 前完成 5 MiB 全量备份，并在主机和 SD 卡各保存一份。
- [ ] boot 写后回读哈希一致，才允许重启。
- [ ] 运行 DT 中 SPI1、lcd_fb 为 `okay`，driver name 为 `st7789v_240x280`。
- [ ] `lcd_fb.ko` 的 hash/srcversion/vermagic 正确，正式速度覆盖参数为 0。
- [ ] lcd_fb framebuffer 为 240×560 virtual、16 bpp。
- [ ] 色条和 LVGL 完整覆盖 240×280，无顶部/底部残留、错行或闪烁。
- [ ] DISP2 保持原状，LVGL 通过 sysfs 自动选择 lcd_fb。
- [ ] 明确认知触摸未适配、软件 PWM 背光未启用、early bootlogo 不属于本轮交付。
