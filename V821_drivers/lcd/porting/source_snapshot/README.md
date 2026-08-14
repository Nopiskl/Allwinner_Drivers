# 最终适配源码快照

本目录保存 2026-08-14 实物验收通过的 ST7789V 240×280 适配源码和配置，目录层级与 Tina SDK 根目录一致。版本标记为 `vendor-seq-20260814-r4-y0-nl280`。

该快照用于归档、审阅和向同版本 SDK 恢复改动，不是脱离 Tina SDK 即可独立构建的源码包。日常编译仍在 SDK 原路径进行，构建过程见 [`../PORTING_AND_BUILD.md`](../PORTING_AND_BUILD.md)。

## 文件范围

| SDK 相对路径 | 归档原因 |
| --- | --- |
| `bsp/drivers/video/sunxi/lcd_fb/panels/st7789v_240x280.c` | 最终面板初始化、280 gate、地址窗口和 open/close flow |
| `bsp/drivers/video/sunxi/lcd_fb/panels/st7789v_240x280.h` | 面板导出声明 |
| `bsp/drivers/video/sunxi/lcd_fb/panels/Kconfig` | 新增独立面板配置项 |
| `bsp/drivers/video/sunxi/lcd_fb/Makefile` | 将面板对象链接进 `lcd_fb.ko` |
| `bsp/drivers/video/sunxi/lcd_fb/panels/panels.c` | 面板注册表 |
| `bsp/drivers/video/sunxi/lcd_fb/panels/panels.h` | 面板注册声明 |
| `bsp/drivers/video/sunxi/lcd_fb/disp_lcd.c` | SPI 速度诊断参数、传输错误返回和 SPI 设备生命周期修正 |
| `bsp/drivers/video/sunxi/lcd_fb/include.h` | DBI、L4I1 和 RGB565 数值枚举参考（未修改的关联头文件） |
| `bsp/drivers/video/sunxi/lcd_fb/logo.c` | lcd_fb 模块构建下的 early bootlogo 兼容处理 |
| `device/config/chips/v821/configs/avaota_f1/linux-5.4-ansc/board.dts` | SPI1 DBI、引脚、panel 和 lcd_fb endpoint 配置 |
| `device/config/chips/v821/configs/avaota_f1/linux-5.4-ansc/bsp_defconfig` | SPI/framebuffer/lcd_fb 模块和面板配置 |
| `platform/thirdparty/gui/lvgl-8/lv_examples/src/lv_conf.h` | LVGL RGB565 色深配置 |
| `platform/thirdparty/gui/lvgl-8/lv_examples/src/lv_drv_conf.h` | 启用 sunxifb 后端 |
| `platform/thirdparty/gui/lvgl-8/lv_drivers/display/sunxifb.c` | 通过 `LV_SUNXIFB_DEVICE` 动态选择 lcd_fb |
| `openwrt/target/v821/v821-avaota_f1/defconfig` | 启用 `lv_examples` 和 sunxifb 双缓冲 |

未归档 `.buildconfig`、`out/` 或生成的内核 `.config`，因为它们包含本机路径或属于可重新生成的构建输出。经过验收的二进制仍只保存在 `V821_drivers/lcd/artifacts/st7789v_240x280/`。

## 完整性检查

在本目录执行：

```sh
sha256sum -c SHA256SUMS
```

`SHA256SUMS` 只覆盖 SDK 源码/配置文件，不包含本说明和清单自身。

## 与当前 SDK 比较

从 SDK 根目录执行以下只读检查：

```sh
export V821_DRIVERS_ROOT=/path/to/Allwinner_Drivers/V821_drivers
export LCD_SNAPSHOT="$V821_DRIVERS_ROOT/lcd/porting/source_snapshot"

while read -r HASH FILE; do
  test "$(sha256sum "$FILE" | awk '{print $1}')" = "$HASH" || {
    echo "DIFF: $FILE"
  }
done < "$LCD_SNAPSHOT/SHA256SUMS"
```

没有 `DIFF` 输出表示 SDK 工作文件与本快照一致。

也可以先预览文件级恢复差异：

```sh
rsync -ainc --no-times --omit-dir-times \
  "$LCD_SNAPSHOT"/{bsp,device,openwrt,platform} \
  ./
```

## 恢复到同版本 SDK

恢复会覆盖 SDK 中的同名文件。先确认目标确实为 V821 `avaota_f1`、Linux `5.4-ansc`，并完成上面的 dry-run，再从 SDK 根目录执行：

```sh
rsync -ac --no-times --omit-dir-times \
  "$LCD_SNAPSHOT"/{bsp,device,openwrt,platform} \
  ./

sha256sum -c "$LCD_SNAPSHOT/SHA256SUMS"
```

恢复后按 `PORTING_AND_BUILD.md` 执行 `./build.sh loadconfig`、内核构建和 LVGL 软件包构建。不要把该快照直接用于不同芯片、板型或内核版本。
