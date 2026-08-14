# ST7789V 240x280 唯一正式部署包

目标：V821 avaota_f1、Linux 5.4.220、P169H002-CTP。

目录：

- `boot/`：首次更新用的 `boot.img` 和便于核查的独立 `sunxi.dtb`。
- `backup/`：设备 boot 的完整回读备份；这是动态恢复材料，不纳入固定 `SHA256SUMS`。
- `modules/`：lcd_fb、SPI panel 和 framebuffer helper 模块。
- `userspace/`：LVGL 独立二进制及可选 IPK。
- `00_preflight.sh`：只读检查设备、DT 状态和本包校验和。
- `01_backup_boot.sh`：完整读取当前 5 MiB boot 到本包 `backup/`。
- `10_load_lcd.sh`：校验正式模块哈希/srcversion，按依赖顺序加载 lcd_fb，自动查找所属 framebuffer 并校验 240x560/16bpp。
- `11_run_lvgl.sh`：自动查找 lcd_fb，通过 `LV_SUNXIFB_DEVICE` 绑定后前台运行 LVGL 示例。
- `12_unload_lcd.sh`：卸载 lcd_fb，供模块重载测试。
- `SHA256SUMS`：所有固定产物校验和。

本包不提供自动刷写脚本，以避免误写 NOR。首次更新必须按 `V821_drivers/lcd/DEPLOYMENT.md` 的授权门和人工校验步骤执行。

运行最小模块集：

```text
modules/fb_sys_fops.ko
modules/lcd_fb_spi_panel.ko
modules/lcd_fb.ko
```

三个 `cfb*.ko` 仅作为 Kconfig 同批产物保留，当前配置不是必需依赖。

本机保留的 DISP2 占用 `/dev/fb0`，lcd_fb 实测为 `/dev/fb1`。两个脚本均根据 sysfs 所属自动选择，不依赖固定编号。

正式 LCD 模块为实物验收通过的 `vendor-seq-20260814-r4-y0-nl280`：Y offset 0，`E4.NL=0x22`（280 gate），SHA-256 `d487d338a2210e9226ff7651f333d70e49b3159418fcbc6d2e27f1e0a4df25e2`，srcversion `67770EC052084657BDF7FE4`。`V821_drivers/lcd/artifacts` 不再保留历史候选，避免误加载。

项目开始前的原始 boot 备份为 `backup/boot_mtd4_19700101_012242.img`，大小 5,242,880 bytes，SHA-256 `a29131e949663f617029f31b6e3e86419ceb46ce6b6dfd4c55f7ed52f6328e81`。文件名中的 1970 来自设备未校时的 RTC，不影响内容。
