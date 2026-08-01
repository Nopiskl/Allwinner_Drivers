# Stock → Meizu E3 v001

## 目的

在重刷后的 Radxa Cubie A7A 上，以官方 A7A Display overlay 拓扑和
Radxa commit `4349013e00f21b703a75d620d8589f301ffc0493` 为依据，部署第一版
Meizu E3 overlay。

## 唯一设备树变量

相对此前能够点亮屏幕的 Meizu E3 `0.1.8` overlay：

- 在 `dsi0_out: port@1` 增加 `reg = <1>`。

其余面板时序、reset GPIO、DSI flags、SEC 触摸、SGM37604A 背光和
GPIO-I2C 配置保持不变。

## 明确不包含

- 不使用 DSI-only debug overlay。
- 不禁用 HDMI 或其子组件。
- 不修改内核 DRM/DSI 驱动。
- 不猜测或 A/B DSI flags、时序、延时和 GPIO。

## Stock 基线

- 地址：`192.168.0.103`
- SSH ED25519：`SHA256:buhWLtpg8L2RWEgVPqf1y1ftqoGbXM0IPp5uAY2UMJ8`
- 内核：`5.15.147-21-a733 #21`
- `radxa-overlays-dkms 0.2.18`
- `rsetup 0.4.27`
- 仅 `HDMI-A-1 → DE-0`，`DE-1` 关闭。
- 无 Meizu backlight/touch 模块与 DSI connector。
- 采集时已运行约 12 分钟；未见 RCU stall、DRM atomic timeout、IOMMU
  fault 或 panic。

## 离线验证

- 基准 DTB：
  `usr/lib/linux-image-5.15.147-21-a733/allwinner/sun60i-a733-cubie-a7a.dtb`
- `fdtoverlay` 合并成功。
- DTBO 反编译确认 `dsi0/ports/port@1/reg = <1>`。
- rsetup metadata 解析成功，compatible 为 `radxa,cubie-a7a`。

SHA256：

```text
762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e  cubie-a7a-meizu-e3-display-v001.dtso
31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832  cubie-a7a-meizu-e3-display-v001.dtbo
2c8028a5498abece4f97ff9b8cdab60e9717141a505304b2879273ecef511dcd  stock base DTB
502fc5d193c591cba003b90847d1b46dbb570f699a457b7ae13a3ced0a923458  merged DTB
992d1cba7de359b2baa736a8e5a65ad2978804bf46c6b2d54002c011e23aedd0  meizu-e3-dkms_0.1.9_all.deb
```

## 回退机制

使用官方 `rsetup`/`u-boot-update` 机制：

- 默认 `l0`：应用 `/boot/dtbo/*.dtbo`。
- rescue `l0r`：`u-boot-update` 故意不写 `fdtoverlays`，可作为 stock
  fallback。
- 软件包安装时只生成 `.dtbo.disabled`；验证后才启用。

## 结果

### 安装与启用

- `meizu-e3-dkms 0.1.9` 已安装，两个 DKMS 模块的 vermagic 与当前
  `5.15.147-21-a733` 匹配。
- 安装后的 `.dtbo.disabled` 与本目录离线验证 DTBO 完全一致。
- 通过 rsetup 的官方底层机制启用，生成配置已经验证：
  - `l0` 只加载 v001；
  - `l0r` 不加载 overlay，保留为 stock 救援项；
  - 启用前配置已备份到板端 `/boot/extlinux/backups/`。

### 首次启动现象

- LightDM 登录界面下 HDMI 与 DSI 都能正常显示。
- 进入桌面会话后，HDMI 变蓝、DSI 变灰白。
- 用户较晚登录导致网络/SSH 较晚可用，不能把 SSH 上线时间当作内核启动
  延迟证据。
- 桌面异常后 `.103` 暂时无网络。
- 已通过本机 CH340 `COM4` 只读抓取 35 秒内核现场，文件为
  `postboot-v001-serial-live.txt`：
  - 内核时间 454.13–489.08 秒；
  - 1402 轮 DE0 `L1 PageTable Invalid`；
  - 无效地址固定为 `0xfa000000`，约 40.1 轮/秒；
  - 476.131 秒出现 RCU expedited stall。

当前结论：v001 能完成面板和登录界面初始化；桌面会话触发双显示配置切换
后，最新 #21 内核复现了旧系统已经确认的 DE0 stale
framebuffer/use-after-unmap 故障链，不是背光或 graph 问题。下一步先从
`l0r` stock rescue 回滚并提取上一次启动日志，不猜改面板 DTS 参数。

串口 Magic SysRq `s/u/b` 未能在 DE0 中断风暴中被处理，必须物理
reset/重新上电；U-Boot 菜单选择 `2` 即为不加载 overlay 的 stock rescue。

### 已完成回滚

- 已通过 `l0r` root rescue 将 v001 恢复为 `.dtbo.disabled`。
- 已运行官方 `u-boot-update`。
- `/boot/dtbo` active overlay 数为 0。
- `l0` 与 `l0r` 均无 `fdtoverlays`。
- DTBO 哈希保持不变。

`failed-v001-journal-kernel.txt` 保存了 persistent journal 的故障起点：

```text
112.922995  first sunxi_de_atomic_flush timeout
119.503159  first IOMMU fault, 0xfae77000
119.527320  continuing IOMMU fault, 0xfa000000
```

两者之间已捕获 116 次 atomic flush timeout，确认 timeout 在先、旧
framebuffer 被解除映射后 DE0 继续扫描在后。

回滚后的 rescue 执行软件 reboot 到达 `reboot: Restarting system`，但
SoC 未重新进入 U-Boot，仍需物理 reset/重新上电。默认项现已是 stock，
无需再次选择 rescue。
