# 5.15 老内核单 DSI 交叉验证

## 固定变量

- 内核：`5.15.147-21-a733`
- 显示 overlay：最初验证版本 `cubie-a7a-meizu-e3-display-v001-reg1-t4.dtso`
- DSI 输入端口：`port@1` / `reg = <1>`
- 背光：只构建、安装 `sgm37604a.ko`
- 触摸：不安装、不加载 `sec_ts.ko`；overlay 中的触摸节点保持原样但没有驱动绑定
- HDMI：不再使用旧的、只禁用 `&hdmi0` 的 `dsi-only-debug` overlay。为了不破坏 DRM component graph，单 DSI 验证时物理断开 HDMI。

## 安全边界

- 所有 overlay 先做 `dtc` 编译及 `fdtoverlay` 离线合并验证。
- 只通过 `u-boot-update` 生成 `/boot/extlinux/extlinux.conf`，不直接用 `sed` 修改它。
- `l0` 加载测试 overlay；`l0r` 必须保持无 overlay 的救援入口。
- 真正重启前备份 extlinux 配置和当前日志，并确认回退脚本可用。

## 原始输入

- SGM37604A 源文件：`../../../../deb/codexline/01_nonburst_dsi_experiment/src/meizu-e3-dkms_0.1.10_staging/usr/src/meizu-e3-dkms-0.1.10/drivers/backlight/sgm37604a.c`
- 源文件 SHA-256：`674F614B35827C95CCF8D87A858F4DC7D8B5E81E12F1F17335A9676840165941`
- overlay：`../../03_new_kernel_overlay_validation/src/build-artifacts/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtso`

本实验的 `../src/sgm-only/` 是专用 DKMS 包骨架，刻意不包含触摸模块。

## 2026-08-01 已完成的板端准备

- 干净基线 boot ID：`e19d9ec4-f957-4590-b3d8-77cef385cb77`
- overlay 启用前只有 HDMI，DSI connector 不存在，致命 DRM/RCU 关键字计数为 0。
- `meizu-e3-sgm37604a/0.1.10` 已针对 `5.15.147-21-a733` 由 DKMS 成功构建、安装。
- `sgm37604a` 已能单独 `modprobe`；`sec_ts` 未安装、未加载。
- 原始 overlay 源文件 SHA-256：`762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e`。
- 5.15 重新编译的 DTBO SHA-256：`31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832`。
- 与 5.15 基础 DTB 离线合并成功；合并树中 `dsi0=okay`、`port@1 reg=1`、SGM 地址 `0x36`、默认亮度 `2000`。
- l0 已配置加载测试 DTBO；l0r 无 `fdtoverlays` 且保留 `single`。
- 板端回退工具：`sudo /usr/local/sbin/rollback-old-kernel-dsi-crosscheck`。
- 尚未执行测试重启；启用配置后 HDMI 仍显示 `connected`，必须物理拔线后再做严格单 DSI 测试。

## 单 DSI 实测结果

- HDMI 物理断开后共完成三轮启动；每轮 DSI 都成功进入 1080×2160 Plasma 桌面，背光正常。
- 严格第三轮 boot ID：`2a2e4660-b03a-4fa7-9673-0296ed6deaf5`。
- 严格第三轮状态：DSI-1 connected/enabled，DE-0 → tcon0；HDMI disconnected/disabled，DE-1 off。
- `sgm37604a` 实际亮度 `2000/4095`；触摸模块未安装、未加载。
- 正常启动和进入桌面后，`sunxi_de_atomic_flush timeout`、IOMMU `PageTable Invalid`、RCU stall、NULL/panic/lockup 均为 0。
- 两次主动 DSI full modeset 都成功恢复，未出现上述灾难链。
- 第一次 full modeset 的关闭阶段出现 4 次 `displl clk unable to lock`，每次约间隔 2 秒，导致第一次关闭耗时约 9 秒；第二次循环没有新增 PLL 错误并约 3 秒完成。这证明老内核仍有首个显示时钟切换缺陷，但它与此前的全机卡死不是同一层级的结果。

## 发现的 rootfs 干扰变量

`radxa-system-config-allwinner 0.6.32` 包含：

1. `hdmi-toggle-once.service`；
2. `/lib/udev/rules.d/60-hdmi-hotplug.rules`；
3. `/usr/bin/hdmi-hotplug-fix`。

udev 规则匹配所有 DRM HOTPLUG，不只 HDMI。HDMI 断开时，helper 最终把第一个 connected 输出选为 DSI-1，并执行 `hdmi-toggle-once force`。前两轮中它确实干预了 DSI。严格第三轮采用：

- 禁用 `hdmi-toggle-once.service`；
- `/etc/udev/rules.d/60-hdmi-hotplug.rules -> /dev/null` 覆盖厂商规则。

严格第三轮没有生成 `/run/hdmi-toggle-once.log` 或 `/run/hdmi-hotplug.log`，证明 workaround 未运行。

板端安装的一键工具：

- `disable-radxa-hdmi-workaround-for-dsi`
- `restore-radxa-hdmi-workaround`

## Windows 主机意外重启

- 01:06 的 Event 41 / Event 6008 表明这是非正常关机。
- WER 记录的实际 bugcheck 是 `0x00000139`，参数 1 为 `0x1d`。
- 转储文件：`C:\Windows\Minidump\080126-13390-01.dmp`（6,397,108 字节）。
- 01:06 附近没有 Event 1074 的软件正常关机记录；这不是本次板端 SSH 命令触发的重启。
