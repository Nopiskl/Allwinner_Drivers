# Meizu E3 v003：先验证 DSI reset 推挽

时间：2026-07-31 15:53（Asia/Shanghai）

## 目的

按用户指定顺序先验证 DSI，再验证 I²C。

本轮相对 v001：

- 删除 `i2c-gpio`、SGM37604A 和 SEC 节点，使 I²C 完全不参与本轮启动；
- DSI 侧唯一功能变量是把 LCD_RESET 从
  `GPIO_ACTIVE_HIGH | GPIO_OPEN_DRAIN` 改成
  `GPIO_ACTIVE_HIGH` 推挽输出。

保持不变：

- v001 已经成功完成初次 DSI enable 的 burst + LPM + NO_EOT；
- 1080×2160、157 MHz、4 lane RGB888；
- v001 的 porch、`vsync-len=4`、0/0 ms exit sequence；
- 官方 A733 DSI/virtual-panel graph 和 `port@1 reg=<1>`；
- HDMI 节点不禁用；
- v001 的 PWM backlight 节点暂时保留，避免在 DSI reset A/B 中同时改变 panel
  backlight 生命周期；它不用于判定最终 Meizu 背光修复。

## 启动前 stock 基线

- 地址：`192.168.0.103`
- boot ID：`85a71e31-bce4-4c68-a6a2-e45f63130a2c`
- 内核：`5.15.147-21-a733 #21`
- `meizu-e3-dkms 0.1.10`
- `radxa-overlays-dkms 0.2.18`
- `/boot/dtbo` 活动 `.dtbo` 数量：0
- v001/v002 均为 `.dtbo.disabled`
- `l0`、`l0r` 均无 `fdtoverlays`
- `l0r` 保留 `single`
- 当前 stock HDMI：1920×1080@60，DE-0
- 当前 boot 错误计数：
  - `sunxi_de_atomic_flush timeout=0`
  - page-table invalid=0
  - `Bug is in DE=0`
  - RCU stall=0
  - panic/NULL fault=0

## 回退要求

- 新产物首先以 `.dtbo.disabled` 安装。
- 启用前备份 `extlinux.conf`。
- 运行官方 `u-boot-update` 生成启动配置，不直接编辑 `extlinux.conf`。
- 默认 `l0` 只允许加载 v003；`l0r` 必须保持无 overlay、`single`。
- 物理重启和 U-Boot 选择由用户执行。

## 待完成

- [x] 预处理、编译、反编译回读
- [x] 与 stock DTB 离线合并
- [x] graph、flags、reset、无 I²C 节点检查
- [x] 安装为 disabled
- [x] 备份并启用
- [ ] 重启后验证实际加载状态
- [ ] 多次冷启动与 modeset 日志

## 离线验证结果

使用板端当前内核头文件预处理和编译：

```text
DTBO:
087ea39502ed529f23c5e39967b820484f2030465157e4df60f7214cffb77b06

stock base DTB:
2c8028a5498abece4f97ff9b8cdab60e9717141a505304b2879273ecef511dcd

merged DTB:
32af6c4512c023c61013fa8b08121fc3493a9988a6e0d81d77d751c311fda962
```

验证结果：

- `fdtoverlay` 合并成功；
- DSI0、DSI combo-PHY、TCON0 均为 `okay`；
- `dsi,flags=0xa03`，与 v001 相同；
- `reset-gpios` 最后一格为 `0x00`，确认是推挽而非 open-drain；
- `port@1/reg=1` 存在，graph endpoint 双向闭合；
- DTBO 与 merged DTS 中没有 `i2c-gpio`、`sgmicro` 或 `sec,sec_ts`。

## 启用结果

板端文件：

```text
/boot/dtbo/cubie-a7a-meizu-e3-display-v003-dsi-pushpull.dtbo
```

SHA256 与离线产物一致。启用前配置备份：

```text
/boot/extlinux/backups/extlinux.conf.pre-v003-dsi-pushpull-20260731-1553
```

`u-boot-update` 后验证：

- 活动 `.dtbo` 恰好 1 个，只是 v003；
- `l0` 只加载 v003；
- `l0r` 没有 `fdtoverlays`；
- `l0r` 保留 `single`；
- `default l0` 和 10 秒菜单保持不变。

本机 COM4 已从 2026-07-31 15:59:35 起以只读方式持续记录到
`serial-v003-boot.log`，等待用户手动物理重启。

## 第一次物理冷启动：登录前现场

- U-Boot 串口确认读取：
  `cubie-a7a-meizu-e3-display-v003-dsi-pushpull.dtbo`
- 系统完成启动并到达串口 login prompt。
- 用户现场观察：HDMI 有输出；Meizu 屏幕无画面、无背光。
- 由于本轮故意没有 SGM 节点，“无背光”符合隔离条件，不能据此判断 DSI 数据
  链路失败。
- 串口在当前 `quiet loglevel=4` 下只记录到 DSI 的 TE IRQ 非致命错误，没有输出
  INFO 级的 connector、combo-PHY 和 configuration-complete 细节。
- 截至登录提示符，串口未出现：
  - `sunxi_de_atomic_flush timeout`
  - IOMMU page-table invalid / `Bug is in DE`
  - RCU stall
  - panic / NULL fault
- 当前网络仍遵循该系统的用户会话行为：未进入桌面前 SSH 不可达。下一步由用户
  在 HDMI 登录桌面，随后立即通过 SSH 采集完整 journal、DRM connector 和
  runtime DT。

## 第一次登录桌面：失败

用户通过 HDMI 登录后，HDMI 立即进入蓝色闪屏。串口同时记录到：

```text
[218.723012] L2 PageTable Invalid
[218.727415] 0x00000000f5697000 is not mapped
[218.733264] Bug is in DE0 module, invalid address: 0xf5697000
[218.746978] L1 PageTable Invalid
[218.751373] 0x00000000f4000000 is not mapped
[218.757227] Bug is in DE0 module, invalid address: 0xf4000000
```

随后约每 24.8 ms 重复一次 `0xf4000000` fault。首次快速统计已经包含：

```text
PageTable Invalid = 1848
Bug is in DE      = 1847
RCU stall         = 2
```

SSH TCP 端口仍接受连接，但内核不能在 5 秒内完成 SSH 握手，符合中断风暴导致的
系统失去调度响应。

本次非常重要的排除结果：

- overlay 中不存在 SGM、SEC 和 `i2c-gpio`，因此本次 DE0/IOMMU 故障与这三个
  对象的 probe、IRQ 或 I²C 操作无关；
- LCD_RESET 已是确定的推挽输出，所以 open-drain reset 可以解释概率性面板
  初始化，却不是登录后 DE/IOMMU 硬锁的充分原因；
- 故障仍严格发生在 LightDM/登录前正常、用户登录后的显示重配置阶段；
- 本次旧 framebuffer 基址变成 `0xf4000000`，此前为 `0xfa000000`，说明错误
  指纹不是某个写死地址，而是“本轮旧 framebuffer 被解除映射后仍被 DE0 扫描”。

当前必须物理重启并选择无 overlay 的 `l0r`，随后禁用 v003。不能在当前 IOMMU
fault storm 中依赖 SSH 或软件 reboot。
