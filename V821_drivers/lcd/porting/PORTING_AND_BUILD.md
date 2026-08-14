# ST7789V 240×280 移植与编译记录

本文记录 P169H002-CTP 屏幕在 V821 `avaota_f1` Tina Linux SDK 上的完整移植与构建过程。完成本文后，继续按 [`DEPLOYMENT.md`](../DEPLOYMENT.md) 创建、上传、加载和回退正式制品；单次回归测试见 [`MANUAL_TEST.md`](../MANUAL_TEST.md)。

## 1. 最终目标与边界

- SoC/板型：Allwinner V821 / `avaota_f1`。
- SDK 内核：Linux 5.4.220，源码配置目录为 `linux-5.4-ansc`。
- 屏幕：P169H002-CTP，1.69 英寸，240 RGB × 280，约 27.97 mm × 32.63 mm。
- 控制器：ST7789V 兼容，初始化依据供应商提供的 ST7789P3 + BOE 序列。
- 总线：V821 SPI1 的 DBI 模式，L4I1，硬件 DCX，与官方接线一致。
- framebuffer：RGB565、双缓冲，所以物理分辨率是 240×280，`virtual_size` 是 240×560，16 bpp。
- 刷新配置：30 fps，像素传输使用 DTS 中的 48 MHz。
- DISP2：保持 SDK/官方教程的原有配置，不因本次 LCD 移植改写。
- 触摸：本次不适配；LVGL 的输入设备打开失败不影响显示验收。
- 背光：`lcd_pwm_used = <0>`，本次不实现软件 PWM 调光；背光由现有硬件接线控制。
- 交付方式：首次用已验收 `boot.img` 使 DTS 生效，后续面板代码优先通过 KO 热更新；LVGL 使用独立二进制或 IPK。

最终实物验收版本标记为：

```text
vendor-seq-20260814-r4-y0-nl280
```

其关键结论是：X offset 0、Y offset 0，GATECTRL `E4.NL = 0x22`，对应 280 gate；顶部和底部均已目测完整覆盖。

## 2. 参考资料与本地输入

在线资料：

- [V821 SPI LCD（DBI）适配教程](https://docs.aw-ol.com/docs/soc/v821/disp/spi-lcd/disp_driver_dbi_spi_1.3inch/)：面板驱动、Kconfig/Makefile、DTS 与 DBI L4I1 的官方适配路径。
- [V821 LVGL 使用说明](https://docs.aw-ol.com/docs/soc/v821/disp/lvgl/lvgl_start/)：`lv_examples` 的配置和 demo 入口。
- [Tina Linux 编译说明](https://docs.aw-ol.com/docs/soc/v821/software/tina-linux-build/)：环境选择、编译与打包入口。
- [ST7789P3 datasheet](https://powershell.one/doneland_test/assets/files/st7789p3_datasheet.pdf) 与 [ST7789V specification](https://dl.espressif.com/dl/schematics/ST7789V_SPEC_V1.0.pdf)：命令、地址窗口和 GATECTRL 位定义的交叉核对资料。

SDK 自带资料：

```text
docs/html/_sources/other/tina/Tina_Linux_SPI_LCD_调试指南/
  Tina_Linux_SPI_LCD_调试指南.md.txt
docs/html/_sources/other/bsp/Linux_SPI_NG_开发指南/
  Linux_SPI_NG_开发指南.md.txt
docs/html/_sources/other/tina/Tina_Linux_图形系统_开发指南/
  Tina_Linux_图形系统_开发指南.md.txt
docs/html/_sources/other/tina/Tina_Linux_系统软件_开发指南/
  Tina_Linux_系统软件_开发指南.md.txt
```

本项目保留的屏幕资料：

```text
V821_drivers/lcd/reference/P169H002-CTP_RevA_20211007.pdf
V821_drivers/lcd/reference/ST7789P3+BOE1.8IPS(WV018LZQ-N80-3QP1)-2.2gamma.txt
```

供应商初始化文件的屏幕名称并非 P169H002-CTP，因此只把它作为控制器/玻璃初始化参考；分辨率、gate 数和最终显示窗口必须结合 P169H002-CTP 规格及实物验证确定。

本次最终适配涉及的源码、配置以及关联枚举头文件已按 SDK 原目录层级归档到 [`source_snapshot/`](source_snapshot/README.md)。该目录带独立 `SHA256SUMS`，可用于审阅、校验或向同版本 SDK 恢复；实际编译仍以 SDK 根目录中的工作文件为准。

## 3. 移植结构

显示路径如下：

```text
LVGL lv_examples
    -> sunxifb (/dev/fbN)
    -> lcd_fb.ko
    -> lcd_fb_spi_panel.ko / SPI core
    -> V821 SPI1 DBI L4I1
    -> ST7789V-compatible panel, 240x280 RGB565
```

DISP2 和 lcd_fb 会同时注册 framebuffer。实测 DISP2 通常是 `/dev/fb0`，lcd_fb 通常是 `/dev/fb1`，但编号不是 ABI，因此正式启动脚本通过 `/sys/class/graphics/fb*` 的设备归属动态查找 lcd_fb。

## 4. SDK 源码修改清单

### 4.1 新增面板驱动

新增源码：

```text
bsp/drivers/video/sunxi/lcd_fb/panels/st7789v_240x280.c
bsp/drivers/video/sunxi/lcd_fb/panels/st7789v_240x280.h
```

驱动导出的面板名为 `st7789v_240x280`，必须与 DTS 的 `lcd_driver_name` 完全一致：

```c
struct __lcd_panel st7789v_240x280_panel = {
	.name = "st7789v_240x280",
	.func = {
		.cfg_open_flow = st7789v_open_flow,
		.cfg_close_flow = st7789v_close_flow,
		.blank = st7789v_blank,
		.set_var = st7789v_set_var,
		.set_addr_win = st7789v_set_addr_win,
	},
};
```

最终初始化主序列为：

| 命令 | 参数 | 用途 |
| --- | --- | --- |
| `11` | 无，随后等待 120 ms | Sleep Out |
| `36` | `00` | MADCTL，当前方向/颜色顺序 |
| `3A` | `05` | RGB565 |
| `B2` | `0C 0C 00 33 33` | Porch setting |
| `B7` | `05` | Gate control |
| `BB` | `21` | VCOM |
| `C0` | `2C` | LCM control |
| `C2` | `01` | VDV/VRH enable |
| `C3` | `15` | VRH |
| `C6` | `0F` | Frame rate control |
| `D0` | `A7`，随后 `A4 A1` | 保留供应商文件中的两次写入 |
| `D6` | `A1` | GCTRL |
| `E0`/`E1` | 供应商 2.2 gamma 表 | 正/负 gamma |
| `E4` | `22 00 00` | 280 gate，从 Gate 0 开始 |
| `21` | 无 | Display inversion on |
| `2A` | `0000..00EF` | 列窗口 0..239 |
| `2B` | `0000..0117` | 行窗口 0..279 |
| `29` | 无 | Display on |
| `2C` | 无 | Memory write |

完整 gamma 参数和实际执行顺序以 [`st7789v_240x280.c`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/panels/st7789v_240x280.c) 为准，不在文档里维护第二份可编译源码。

驱动实现还包括：

- 偏移常量 `ST7789V_X_OFFSET = 0`、`ST7789V_Y_OFFSET = 0`。
- RESET 时序为高 100 ms、低 100 ms、高 120 ms。
- open flow：上电/引脚 -> 面板初始化 -> 黑屏清除 -> 背光开启。
- close flow：背光关闭 -> Display Off/Sleep In -> RESET 拉低/引脚关闭 -> 电源关闭。
- `set_addr_win` 每次更新 `2A/2B` 后发送 `2C`，支持 framebuffer 脏矩形刷新。
- 命令和每个参数都检查 SPI 返回值；初始化失败会输出 `ST7789 init ... aborted`，不会假装成功。

### 4.2 面板 Kconfig、Makefile 与注册表

[`panels/Kconfig`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/panels/Kconfig) 新增：

```kconfig
config LCD_FB_SUPPORT_ST7789V_240X280
	bool "LCD FB support ST7789V 240x280 panel"
	default n
```

这里使用独立的 `LCD_FB_...` 配置名，避免与 SDK 另一套 DISP2 面板驱动的 ST7789V 选项冲突。

[`lcd_fb/Makefile`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/Makefile) 把面板对象链接进 `lcd_fb.ko`：

```make
lcd_fb-${CONFIG_LCD_FB_SUPPORT_ST7789V_240X280} += panels/st7789v_240x280.o
```

[`panels.c`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/panels/panels.c) 和 [`panels.h`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/panels/panels.h) 都在 `IS_ENABLED(CONFIG_LCD_FB_SUPPORT_ST7789V_240X280)` 下注册/声明 `st7789v_240x280_panel`。这样 `CONFIG_LCD_FB=m`、面板布尔选项为 `y` 时，面板实现被正确链接到模块。

### 4.3 lcd_fb 框架修正

[`disp_lcd.c`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/disp_lcd.c) 做了以下面板调试和模块生命周期修正：

- 新增 `lcd_fb.ko` 参数 `spi_speed_hz`，`0` 表示保留 DTS 速度；有效诊断范围为 100 kHz..100 MHz。
- 初始化命令/参数正常限制在 20 MHz；若调试覆盖值低于 20 MHz，则命令也使用更低值。像素 DMA 正式版仍使用 DTS 的 48 MHz。
- 命令/参数写入返回 `spi_sync_transfer()` 的真实错误，使面板初始化可中止并留下可靠日志。
- 通过 DT 找到 SPI panel 后保留设备引用，直到 lcd_fb 最终退出才 `put_device()`；模块 disable/re-enable 期间不错误注销 DTS 创建的 SPI 设备。

正式包必须以 `spi_speed_hz=0` 加载。低速值仅用于排查信号完整性，不能作为验收版本。

[`logo.c`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/logo.c) 对 `MODULE` 构建关闭 early bootlogo reserve 映射，返回 `-EOPNOTSUPP`。原因是 early parameter 只适用于内建驱动，而且 RISC-V 模块路径会通过 `pgprot_noncached()` 引入未导出的 `pa_msb` 符号。本次目标是可热加载 lcd_fb KO，内核早期 logo 不在适配范围内。

## 5. DTS 修改

实际文件为：

```text
device/config/chips/v821/configs/avaota_f1/linux-5.4-ansc/board.dts
```

上一级 `device/config/chips/v821/configs/avaota_f1/board.dts` 是指向该文件的符号链接。不要同时编辑两份。

在 `&pio` 中增加 SPI1 DBI 引脚：

```dts
dbi1_pins_default: dbi1@0 {
	pins = "PD1", "PD2", "PD3"; /* cs, clk, sdo */
	function = "spi1";
	allwinner,drive = <3>;
};

dbi1_pins_dcx: dbi1@1 {
	pins = "PD5"; /* dcx */
	function = "spi1_hold";
	allwinner,drive = <3>;
	bias-pull-up;
};

dbi1_pins_sleep: dbi1@2 {
	pins = "PD1", "PD2", "PD3", "PD5";
	function = "io_disabled";
};
```

启用 SPI1 DBI，并增加 panel 子节点：

```dts
&spi1 {
	pinctrl-0 = <&dbi1_pins_default &dbi1_pins_dcx>;
	pinctrl-1 = <&dbi1_pins_sleep>;
	pinctrl-names = "default", "sleep";
	sunxi,spi-bus-mode = <SUNXI_SPI_BUS_DBI>;
	sunxi,spi-cs-mode = <SUNXI_SPI_CS_AUTO>;
	status = "okay";

	spi_panel_spi1: slave@0 {
		device_type = "spi-panel";
		compatible = "allwinner,spi-panel";
		reg = <0>;
		spi-max-frequency = <100000000>;
		lcd_used = <1>;
		lcd_model_name = "P169H002-CTP";
		lcd_driver_name = "st7789v_240x280";
		lcd_if = <1>;
		lcd_dbi_if = <2>; /* L4I1 */
		lcd_data_speed = <48>;
		lcd_spi_bus_num = <1>;
		lcd_x = <240>;
		lcd_y = <280>;
		lcd_pixel_fmt = <10>; /* RGB565 framebuffer */
		lcd_dbi_fmt = <2>; /* RGB565 wire format */
		lcd_rgb_order = <0>;
		lcd_width = <28>;
		lcd_height = <33>;
		lcd_pwm_used = <0>;
		fb_buffer_num = <2>;
		lcd_backlight = <100>;
		lcd_fps = <30>;
		lcd_dbi_te = <0>;
		lcd_dbi_clk_mode = <0>;
		lcd_gpio_0 = <&pio PD 4 GPIO_ACTIVE_LOW>; /* reset */
		status = "okay";
	};
};
```

最后启用 lcd_fb 并连接 graph endpoint：

```dts
&lcd_fb {
	status = "okay";
	port {
		#address-cells = <1>;
		#size-cells = <0>;
		spi_panel0: endpoint@0 {
			reg = <0>;
			remote-endpoint = <&spi_panel_spi1>;
		};
	};
};
```

数字枚举可在 [`include.h`](source_snapshot/bsp/drivers/video/sunxi/lcd_fb/include.h) 复核：`lcd_if=1` 是 DBI，`lcd_dbi_if=2` 是 L4I1，`lcd_pixel_fmt=10` 是 RGB565。

只有 SPI1 支持本平台所需 DBI 路径，因此不能把这组配置机械移动到其他 SPI 控制器。PD4 是普通 RESET GPIO，PD5 是 DBI 硬件 DCX。

## 6. 内核配置修改

板级内核配置文件：

```text
device/config/chips/v821/configs/avaota_f1/linux-5.4-ansc/bsp_defconfig
```

最终相关配置：

```config
CONFIG_AW_SPI_NG=y
CONFIG_FB=y
CONFIG_LCD_FB=m
CONFIG_LCD_FB_SUPPORT_ST7789V_240X280=y
# CONFIG_LCD_SUPPORT_KLD2844B is not set
```

执行 `./build.sh loadconfig` 后，还必须在生成配置中看到：

```config
CONFIG_AW_SPI_NG_DBI=y
```

核对命令：

```sh
rg '^(CONFIG_AW_SPI_NG=|CONFIG_AW_SPI_NG_DBI=|CONFIG_FB=|CONFIG_LCD_FB=|CONFIG_LCD_FB_SUPPORT_ST7789V_240X280=|# CONFIG_LCD_SUPPORT_KLD2844B)' \
  device/config/chips/v821/configs/avaota_f1/linux-5.4-ansc/bsp_defconfig \
  out/v821/kernel/build/.config
```

`CONFIG_LCD_FB=m` 是 KO 热更新的前提；SPI NG/DBI 留在内核中，DTS 的使能也必须通过 boot 更新后才会出现在运行设备树。

## 7. LVGL 修改与配置

[`lv_conf.h`](source_snapshot/platform/thirdparty/gui/lvgl-8/lv_examples/src/lv_conf.h) 使用：

```c
#define LV_COLOR_DEPTH 16
#define LV_COLOR_16_SWAP 0
```

[`lv_drv_conf.h`](source_snapshot/platform/thirdparty/gui/lvgl-8/lv_examples/src/lv_drv_conf.h) 启用 `USE_SUNXIFB=1`；编译时默认路径仍可为 `/dev/fb0`。

由于 DISP2 与 lcd_fb 并存，[`sunxifb.c`](source_snapshot/platform/thirdparty/gui/lvgl-8/lv_drivers/display/sunxifb.c) 增加环境变量选择：

```c
const char *fb_path = getenv("LV_SUNXIFB_DEVICE");

if (fb_path == NULL || fb_path[0] == '\0')
	fb_path = SUNXIFB_PATH;
```

正式运行脚本先找出 lcd_fb 所属节点，再导出 `LV_SUNXIFB_DEVICE=/dev/fbN`，所以不会误画到 DISP2。

OpenWrt 板级配置 [`defconfig`](source_snapshot/openwrt/target/v821/v821-avaota_f1/defconfig) 中启用：

```config
CONFIG_PACKAGE_lv_examples=y
CONFIG_LVGL8_USE_SUNXIFB_DOUBLE_BUFFER=y
# CONFIG_LVGL8_USE_SUNXIFB_CACHE is not set
# CONFIG_LVGL8_USE_SUNXIFB_G2D is not set
# CONFIG_LVGL8_USE_SUNXIFB_G2D_ROTATE is not set
# CONFIG_LVGL8_USE_SUNXIFB_DIRECT_MODE is not set
```

双缓冲对应设备上的 `virtual_size=240,560`。本轮先使用最直接的软件绘制路径，避免 G2D、旋转和 cache 额外变量。

若需要按官方教程从菜单重新选择，可在加载 `.buildconfig` 后运行 `make menuconfig`，在 GUI/Littlevgl 相关菜单中选中 `lv_examples`，保存后再核对上面的板级 defconfig；正式记录以配置符号而不是菜单显示文字为准。

## 8. 显示边界问题的定位过程

本轮依次排除了三类问题：

1. 初次只有背光/黑屏时，最终发现 RESET 接线松动；这不是软件时序本身造成的。修复接线后，模块加载会先出现随机显存/雪花，初始化和清屏后消失，随后 LVGL 正常显示。
2. 首轮参考常见 240×280 模组使用 Y offset 20，结果顶部有一条未覆盖、底部图像被裁切；说明该屏的可见区并不从 GRAM Y=20 开始。
3. 改成 Y offset 0 后，顶部恢复，但供应商序列的 `E4=23 00 00` 配置了 288 gate，底部约 8 行仍不完整。尝试 Y=10 会重新造成顶部未覆盖。

最终将 Y offset 保持为 0，并把 `E4` 改为 `22 00 00`，使 gate 数与 280 行物理屏一致。实物确认上下边界均完整。因此不要再用常见模组的 `Y=20` 或以“目测十行”为依据添加偏移。

## 9. SDK 构建环境

所有命令从 SDK 根目录执行：

```sh
export LCD_SDK_ROOT=/path/to/tina-v821-v1.3
cd "$LCD_SDK_ROOT"
source build/envsetup.sh
lunch
```

在 `lunch` 中选择与下列目标一致的 `avaota_f1` 配置。已有 `.buildconfig` 时，可在新的 Shell 中直接加载并校验：

```sh
source .buildconfig

test "$LICHEE_ARCH" = riscv32
test "$LICHEE_KERN_VER" = linux-5.4-ansc
test "$LICHEE_CHIP" = sun300iw1p1
test "$LICHEE_IC" = v821
test "$LICHEE_BOARD" = avaota_f1
test "$LICHEE_FLASH" = nor
```

不要在未检查 `.buildconfig` 的情况下直接编译，以免把其他板型的输出复制进正式包。

## 10. 编译内核、DTB、boot.img 和 KO

首次应用板级配置，或修改 `bsp_defconfig` 后：

```sh
cd "$LCD_SDK_ROOT"
source .buildconfig
./build.sh loadconfig
./build.sh kernel
```

只修改面板 C 文件或 lcd_fb 框架时：

```sh
cd "$LCD_SDK_ROOT"
source .buildconfig
./build.sh kernel
```

主要输出：

```text
out/v821/avaota_f1/openwrt/boot.img
out/v821/avaota_f1/openwrt/sunxi.dtb
out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb.ko
out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb_spi_panel.ko
out/v821/kernel/staging/lib/modules/5.4.220/fb_sys_fops.ko
out/v821/kernel/staging/lib/modules/5.4.220/cfbcopyarea.ko
out/v821/kernel/staging/lib/modules/5.4.220/cfbfillrect.ko
out/v821/kernel/staging/lib/modules/5.4.220/cfbimgblt.ko
```

检查构建结果：

```sh
stat -c '%s %n' \
  out/v821/avaota_f1/openwrt/boot.img \
  out/v821/avaota_f1/openwrt/sunxi.dtb \
  out/v821/kernel/staging/lib/modules/5.4.220/{lcd_fb.ko,lcd_fb_spi_panel.ko,fb_sys_fops.ko}

sha256sum \
  out/v821/avaota_f1/openwrt/boot.img \
  out/v821/avaota_f1/openwrt/sunxi.dtb \
  out/v821/kernel/staging/lib/modules/5.4.220/{lcd_fb.ko,lcd_fb_spi_panel.ko,fb_sys_fops.ko}

modinfo out/v821/kernel/staging/lib/modules/5.4.220/lcd_fb.ko | \
  rg '^(filename|version|srcversion|depends|vermagic):'
```

正式 `lcd_fb.ko` 的验收属性为：

```text
size:       97084
sha256:     d487d338a2210e9226ff7651f333d70e49b3159418fcbc6d2e27f1e0a4df25e2
srcversion: 67770EC052084657BDF7FE4
depends:    fb_sys_fops
vermagic:   5.4.220 preempt mod_unload riscv
```

注意：每次重新运行内核构建，`boot.img` 可能因打包内容或构建元数据变化而改变哈希。2026-08-14 当前工作目录后续构建输出的 `boot.img` 哈希为 `763b63376bbf69fca5646f97a8f4675267b463dcf0ae2bc18e12729c074ed68a`，而正式包中已上板验证的镜像哈希为 `7791017db6ea3959cf1d2f37575d0693a7b10bc94ee7e0d151c4b93aaef105bc`。后续构建产物未经重新烧写和实物回归，不得覆盖正式包。

若需要生成完整烧录固件，官方入口是：

```sh
./build.sh
pack
```

本项目日常 KO/LVGL 更新不需要完整固件，也不应因此重刷整机。

## 11. 编译 LVGL demo

```sh
cd "$LCD_SDK_ROOT"
source .buildconfig
make -C openwrt/openwrt defconfig
make -C openwrt/openwrt package/lv_examples/clean
make -C openwrt/openwrt package/lv_examples/compile -j8
```

正式复制来源应使用经过 OpenWrt package install/strip 阶段的二进制：

```text
out/v821/avaota_f1/openwrt/build_dir/target/lv_examples/
  ipkg-riscv32_a27l2_rv32imac_zicsr_zifencei/lv_examples/usr/bin/lv_examples
```

IPK 输出：

```text
out/v821/avaota_f1/openwrt/extra/packages/
  riscv32_a27l2_rv32imac_zicsr_zifencei/base/
  lv_examples_8.3.2-1_riscv32_a27l2_rv32imac_zicsr_zifencei.ipk
```

检查：

```sh
file out/v821/avaota_f1/openwrt/build_dir/target/lv_examples/\
ipkg-riscv32_a27l2_rv32imac_zicsr_zifencei/lv_examples/usr/bin/lv_examples

sha256sum out/v821/avaota_f1/openwrt/build_dir/target/lv_examples/\
ipkg-riscv32_a27l2_rv32imac_zicsr_zifencei/lv_examples/usr/bin/lv_examples
```

预期是使用 `/lib/ld-musl-riscv32.so.1` 的 stripped 32-bit RISC-V ELF。`lv_examples` 的数字参数选择 demo；本项目使用 `1` 验证 music demo。

## 12. 构建完成后的交接

构建输出不能直接视为正式版。推荐顺序是：

1. 记录源码版本、产物大小、SHA-256、`modinfo`。
2. 把新 KO 放到 SD 卡的独立实验目录，不覆盖正式 `modules/`。
3. 按 `MANUAL_TEST.md` 卸载正式模块、加载实验模块，检查日志、色条和 LVGL。
4. 验证颜色、方向、顶部/底部覆盖、持续刷新和重载。
5. 只有实物验收通过后，才把同一批产物收录到唯一正式包并更新 `SHA256SUMS` 和脚本锁定值。
6. 首次 DTS 变更才更新 boot；普通面板初始化迭代只更换 KO。

正式包如何由这些输出建立、如何经 ADB 上传，以及 boot 的备份、烧写和回退，全部接续记录在 [`DEPLOYMENT.md`](../DEPLOYMENT.md)。
