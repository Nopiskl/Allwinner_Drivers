# A7A 5.15 DSI 交叉验证与后续双屏测试

更新时间：2026-08-01

## 固定测试版本

- 开发板：Radxa Cubie A7A，`192.168.0.103`
- rootfs：Debian 11 Bullseye
- 旧内核：`5.15.147-21-a733 #21`
- 测试 overlay：`cubie-a7a-meizu-e3-display-v001-reg1-5.15.dtbo`
- overlay 源文件 SHA-256：`762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e`
- 5.15 DTBO SHA-256：`31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832`
- 变量仅为最初 v001 加官方 A7A DSI graph 所需的 `dsi0/ports/port@1 reg = <1>`；未加入后续 non-burst、push-pull reset、硬件 TWI 等试验。

## 启动与回退结构

- `l0`：测试系统，加载上述唯一 active DTBO。
- `l0r`：rescue target，不含 `fdtoverlays`，保留 `single`。
- extlinux 由 `u-boot-update` 生成，没有手工修改。
- overlay 回退：`sudo /usr/local/sbin/rollback-old-kernel-dsi-crosscheck`

## 驱动状态

- 仅安装 `meizu-e3-sgm37604a/0.1.10` DKMS。
- `sgm37604a` 设置为开机加载；严格测试中的实际亮度为 `2000/4095`。
- 没有安装或加载 `sec_ts`；触摸不属于本轮变量。

## 严格单 DSI 结论

HDMI 物理断开后共完成三轮启动。前两轮虽然视觉和桌面均正常，但受到 rootfs HDMI workaround 干预；严格第三轮屏蔽该干预后仍正常启动、进入完整 Plasma，并完成两次 DSI full modeset。

严格第三轮的状态：

- boot ID：`2a2e4660-b03a-4fa7-9673-0296ed6deaf5`
- DSI-1：connected/enabled，1080×2160@59，DE-0 → tcon0。
- HDMI-A-1：disconnected/disabled，DE-1 off。
- `sunxi_de_atomic_flush timeout`：0。
- IOMMU `PageTable Invalid`：0。
- RCU stall、NULL/panic、soft/hard lockup：0。
- DE-0 `err=0`。

第一次主动 DSI off/on 在关闭阶段出现 4 次 `displl clk unable to lock`，约每 2 秒一次，使第一次关闭耗时约 9 秒；随后成功恢复。第二次 off/on 没有新增 PLL 错误，约 3 秒完成。说明旧 5.15 仍有首次完整显示时钟切换缺陷，但单 DSI 下没有进入此前的 `atomic timeout → stale framebuffer → IOMMU fault storm → RCU stall` 故障链。

因此，严格结论是：

1. 旧内核启用 DSI 并不必然卡死。
2. 单 DSI 正常启动和桌面路径已经通过。
3. 老内核仍有显示 PLL/时钟切换缺陷，可能参与慢切换或概率性黑屏。
4. 此前全机硬锁死仍主要指向旧 sunxi DRM/DE RCQ atomic 错误处理；双 CRTC、输出热插拔或用户态 modeset 是放大条件，而不是 DSI 面板本身。

## 新发现的 rootfs 干扰变量

`radxa-system-config-allwinner 0.6.32` 自带：

```text
所有 DRM HOTPLUG
  -> /lib/udev/rules.d/60-hdmi-hotplug.rules
  -> /usr/bin/hdmi-hotplug-fix
  -> /usr/bin/hdmi-toggle-once force
```

该规则并不限于 HDMI。HDMI 断开时，脚本会回退选择第一个 connected 输出，即 DSI-1，并尝试错误的 1280×720 后再执行 `--auto`，从而额外干预 DSI atomic 状态。

严格测试中采用可逆隔离：

- `hdmi-toggle-once.service` disabled；
- `/etc/udev/rules.d/60-hdmi-hotplug.rules -> /dev/null`。

工具：

- 重新隔离：`sudo /usr/local/sbin/disable-radxa-hdmi-workaround-for-dsi`
- 恢复厂商行为：`sudo /usr/local/sbin/restore-radxa-hdmi-workaround`

## DSI + HDMI 对照结果

同一套 l0/l0r、同一个 v001-reg1 overlay 和同一个 SGM-only 背光环境下，完成了两种双屏路径对照。

### 已运行桌面中热接并启用双屏：通过

- DSI-1：1080x2160，DE-0/tcon0。
- HDMI-1：1920x1080，DE-1/tcon4。
- X framebuffer：3000x2160，双 CRTC 共用 paddr `0xf0000000`。
- 两路 `err=0`，用户确认视觉正常；没有 IOMMU/RCU/NULL/panic/atomic timeout。

### HDMI 保持连接，冷启动后从 SDDM 登录 Plasma：复现硬锁死

- 登录界面正常；登录后 DSI 与 HDMI 同时冻结。
- 串口在 `34.087194 s` 首次报告 DE0 `L2 PageTable Invalid`，地址 `0xfa1f5000`。
- 随后 DE0 连续访问未映射的 `0xfa000000`，记录 3536 次 L1 页表错误与 3537 次 DE0 invalid-address。
- CPU6 在 `55.187693 s`、`118.210362 s` 两次报告 RCU self-detected stall；错误风暴至少持续到 `121.611 s`。
- DE1 invalid-address 为 0；本次没有直接打印 atomic_flush timeout、NULL pointer 或 soft lockup。
- 厂商 `hdmi-toggle-once` service 和广义 DRM hotplug udev 规则在本轮都保持禁用，因此不是直接触发者。

## 当前最强结论

老 5.15 的核心问题不是“加载 DSI overlay 就必然异常”，也不是 GPU 绘制本身。故障窗口已经收窄到：双输出在启动阶段存在时，显示管理器登录界面切换到用户桌面所触发的双 CRTC framebuffer/atomic 状态交接。

DE0 最终扫描了一个已经没有 IOMMU 映射的 framebuffer 地址。结合此前同型故障中驱动打印的 `map:0` / `unmap-ts` 历史，这强烈指向 sunxi DRM/DE/RCQ 中 framebuffer 生命周期与硬件提交完成之间缺少正确同步。随后高频 DE0 异常占住 CPU6 并造成 RCU stall，所以 HDMI 虽未单独产生 DE1 页表错误，也会随整机冻结。

这也统一解释了当前看似矛盾的结果：

1. 单 DSI 能多次正常登录，因为没有双 CRTC 会话重配置压力。
2. 桌面启动后再热接 HDMI 能正常，因为这条路径没有发生 SDDM 到 Plasma 的所有权/缓冲区交接。
3. HDMI 从开机即存在时，登录后立刻失败，因为桌面会话建立时同时重建双输出布局和 scanout framebuffer，命中老内核的同步缺陷。

完整构建物、三轮单 DSI dmesg、串口记录、extlinux 配置和回退脚本位于：

`test_files/mainline/05_old_kernel_single_dsi_crosscheck/`

双屏热插通过证据和冷启动登录卡死串口位于：

`test_files/mainline/06_old_kernel_dual_display_crosscheck/`
