# 编译、KO 热更新与回归测试

适用目标：V821 `avaota_f1`、Linux 5.4.220、P169H002-CTP。源码移植和构建背景见 [`porting/PORTING_AND_BUILD.md`](porting/PORTING_AND_BUILD.md)；正式版本、固定哈希和部署命令见 [`DEPLOYMENT.md`](DEPLOYMENT.md)。

## 1. 先判断需要更新什么

| 修改内容 | 构建 | 设备更新 | 是否刷 boot |
| --- | --- | --- | --- |
| 面板初始化、offset、MADCTL、延时 | `./build.sh kernel` | `lcd_fb.ko` | 否 |
| 编入 lcd_fb 模块的框架代码 | `./build.sh kernel` | 同批相关 KO | 通常否 |
| DTS、SPI DBI 内建代码、内建配置 | `./build.sh kernel` | `boot.img` | 是 |
| LVGL/sunxifb/示例 | LVGL 软件包 | `lv_examples` | 否 |
| rootfs 或系统模块集 | 对应系统构建 | rootfs/固件 | 本文不处理 |

当前设备 DT 已启用 SPI1/lcd_fb。只改面板代码时，不要因为构建目录生成了新 boot 就重复刷写。

## 2. 环境预检

```sh
export V821_DRIVERS_ROOT=/path/to/Allwinner_Drivers/V821_drivers
export LCD_SDK_ROOT=/path/to/tina-v821-v1.3
export LCD_ADB_SERIAL=YOUR_ADB_SERIAL
cd "$LCD_SDK_ROOT"

test -f .buildconfig
test -x build.sh
source .buildconfig
test "$LICHEE_IC" = v821
test "$LICHEE_BOARD" = avaota_f1
test "$LICHEE_KERN_VER" = linux-5.4-ansc
adb -s "$LCD_ADB_SERIAL" shell \
  'id; uname -a; mount | grep /mnt/extsd; cat /proc/mtd'
```

继续前应确认 ADB 状态为 `device`、SD 卡可写、运行内核为 5.4.220。

## 3. 编译内核与模块

普通面板源码迭代：

```sh
cd "$LCD_SDK_ROOT"
./build.sh kernel
```

只有板级配置需要重新装载时才执行：

```sh
./build.sh loadconfig
./build.sh kernel
```

核对配置：

```sh
rg '^(CONFIG_LCD_FB=|CONFIG_LCD_FB_SUPPORT_ST7789V_240X280=|CONFIG_AW_SPI_NG=|CONFIG_AW_SPI_NG_DBI=)' \
  out/v821/kernel/build/.config
```

核对产物：

```sh
stat -c '%s %n' \
  out/v821/avaota_f1/openwrt/boot.img \
  out/v821/avaota_f1/openwrt/sunxi.dtb \
  out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb.ko \
  out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb_spi_panel.ko \
  out/v821/kernel/staging/lib/modules/5.4.220/fb_sys_fops.ko

sha256sum \
  out/v821/avaota_f1/openwrt/boot.img \
  out/v821/avaota_f1/openwrt/sunxi.dtb \
  out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb.ko

modinfo out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb.ko
```

新构建的哈希可以变化；必须记录本轮实际值，不能为匹配旧记录而修改文件。

## 4. 编译 LVGL

```sh
cd "$LCD_SDK_ROOT"
source .buildconfig
make -C openwrt/openwrt defconfig
make -C openwrt/openwrt package/lv_examples/clean
make -C openwrt/openwrt package/lv_examples/compile -j8
```

二进制：

```text
out/v821/avaota_f1/openwrt/build_dir/target/lv_examples/ipkg-riscv32_a27l2_rv32imac_zicsr_zifencei/lv_examples/usr/bin/lv_examples
```

使用 `file` 和 `sha256sum` 检查 RISC-V 32 位 ELF 和本轮哈希。

## 5. 测试新 KO，不覆盖正式包

为每轮实验建立独立设备目录：

```sh
export LCD_RUN=manual_run01
adb -s "$LCD_ADB_SERIAL" shell \
  "mkdir -p /mnt/extsd/st7789v_240x280/$LCD_RUN/modules"
adb -s "$LCD_ADB_SERIAL" push \
  out/v821/kernel/staging/lib/modules/5.4.220/fb_sys_fops.ko \
  out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb_spi_panel.ko \
  out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb.ko \
  "/mnt/extsd/st7789v_240x280/$LCD_RUN/modules/"
adb -s "$LCD_ADB_SERIAL" shell \
  "sha256sum /mnt/extsd/st7789v_240x280/$LCD_RUN/modules/*.ko"
```

先停止 LVGL 并卸载正式模块：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'PIDS=$(pidof lv_examples 2>/dev/null || true); [ -z "$PIDS" ] || kill $PIDS'
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/12_unload_lcd.sh'
```

加载同一轮 KO：

```sh
adb -s "$LCD_ADB_SERIAL" shell "
set -eu
RUN=/mnt/extsd/st7789v_240x280/$LCD_RUN
insmod \"\$RUN/modules/fb_sys_fops.ko\"
insmod \"\$RUN/modules/lcd_fb_spi_panel.ko\"
insmod \"\$RUN/modules/lcd_fb.ko\"
sleep 1
cat /sys/module/lcd_fb/srcversion
dmesg | tail -n 120
"
```

不要把未通过实物回归的 KO 复制到 `$V821_DRIVERS_ROOT/lcd/artifacts` 或设备正式 `modules/`。

## 6. framebuffer 与显示回归

识别 lcd_fb，不假定固定 `/dev/fb1`：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
set -eu
for FB_SYS in /sys/class/graphics/fb*; do
    [ -e "$FB_SYS" ] || continue
    case "$(readlink "$FB_SYS" 2>/dev/null || true)" in
        *lcd_fb*)
            echo "device=/dev/${FB_SYS##*/}"
            cat "$FB_SYS/virtual_size"
            cat "$FB_SYS/bits_per_pixel"
            ;;
    esac
done
'
```

预期为 240x560 virtual、16 bpp。

色条测试：

```sh
adb -s "$LCD_ADB_SERIAL" shell '
grep "44026000.spi" /proc/interrupts || true
echo 0 > /sys/class/lcd_fb/lcd_fb/attr/screenid
echo 1 > /sys/class/lcd_fb/lcd_fb/attr/colorbar
sleep 1
grep "44026000.spi" /proc/interrupts || true
dmesg | tail -n 100
'
```

LVGL 回归可继续使用正式二进制：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/11_run_lvgl.sh 1'
```

实物检查至少包括：颜色、方向、顶部/底部完整覆盖、错行、闪烁和持续刷新稳定性。

## 7. 日志采集

```sh
adb -s "$LCD_ADB_SERIAL" shell '
mkdir -p /mnt/extsd/st7789v_240x280/logs
dmesg > /mnt/extsd/st7789v_240x280/logs/dmesg.txt
cat /proc/modules > /mnt/extsd/st7789v_240x280/logs/modules.txt
cat /proc/interrupts > /mnt/extsd/st7789v_240x280/logs/interrupts.txt
for FB_SYS in /sys/class/graphics/fb*; do
    [ -e "$FB_SYS" ] || continue
    NAME=${FB_SYS##*/}
    {
        readlink "$FB_SYS" || true
        cat "$FB_SYS/virtual_size" 2>/dev/null || true
        cat "$FB_SYS/bits_per_pixel" 2>/dev/null || true
    } > "/mnt/extsd/st7789v_240x280/logs/$NAME.txt"
done
sync
'
adb -s "$LCD_ADB_SERIAL" pull \
  /mnt/extsd/st7789v_240x280/logs \
  "$V821_DRIVERS_ROOT/lcd/device_logs/"
```

`cfg_panel_info is NULL` 是未提供可选 gamma 回调；`pwm device hdl is NULL` 对当前无软件背光控制设计是预期日志。真正需要阻塞的是 SPI timeout/error、ST7789 init aborted、DMA error、oops 或 framebuffer 尺寸不符。

## 8. 恢复正式版

实验结束后执行：

```sh
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/12_unload_lcd.sh'
adb -s "$LCD_ADB_SERIAL" shell \
  'sh /mnt/extsd/st7789v_240x280/10_load_lcd.sh'
```

正式脚本会重新锁定正式模块哈希、srcversion 和 DTS 48 MHz。若修改涉及 DTS/内建内核，再严格按 `DEPLOYMENT.md` 的 boot 备份、授权、写入和回读流程执行。
