# t4 / 6.6：重新验证最初的 v001 `reg = <1>`

开始时间：2026-07-31 17:08（Asia/Shanghai）

## 本轮范围

只验证最早的 graph 修复版：

```dts
dsi0_out: port@1 {
	reg = <1>;
	...
};
```

不带入后续候选：

- 不改为 non-burst（旧 v002）。
- 不把 reset 改为 push-pull。
- 不删除 I2C/SGM/SEC 节点，不制作 DSI-only debug 版。
- 不修改内核 DRM/DSI 驱动。
- 启动时的电源、供电和 regulator 类告警按用户要求排除在本轮及后续分析范围外。

## 新系统基线

- 主机：`radxa-cubie-a7a`，SSH `radxa@192.168.0.103`。
- 系统：Debian 13（Trixie）。
- 内核：`6.6.98-3-aw2511 #3`。
- 根文件系统 UUID：`653db195-501c-4b19-a720-2fc8f1382665`。
- overlay 包：`radxa-overlays-dkms 0.2.25`。
- 基础 DTB：
  `/usr/lib/linux-image-6.6.98-3-aw2511/allwinner/sun60i-a733-cubie-a7a.dtb`。
- 基础 DTB SHA256：
  `abf2114c2a716cdbb95a4ab5d53674f8bdd9676e2a79e652768c856b96434734`。
- stock 桌面为 Plasma X11；未加载任何 DTBO 时，HDMI-A-1 为
  1920x1080@60。
- stock 当前启动日志中以下事件均为 0：
  `sunxi_de_atomic_flush timeout`、`PageTable Invalid`、`Bug is in DE`、
  RCU stall、NULL pointer dereference、kernel panic 和 soft lockup。

完整基线：

```text
stock-snapshot/radxa-a733-preflash-current.tar.gz
SHA256=78b3d05dc02005980456b4bc72c0e0f8dacb5b0e023466e5c51cac4be4a73319
```

## 历史版本和官方源码对比

本轮源文件来自历史 v001：

```text
../../01_initial_overlay_validation/src/cubie-a7a-meizu-e3-display-v001.dtso
SHA256=762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e
```

`meizu-e3-dkms 0.1.8 -> 0.1.9` 的设备树差异已重新复核。排除 metadata
文本和空格格式后，唯一设备树功能变化是在
`dsi0_out: port@1` 中增加 `reg = <1>`。

已从这台 t4 板端保存实际安装的官方 0.2.25 源码、官方 DTBO、基础 DTB、
原始 `extlinux.conf` 和 `/etc/default/u-boot` 到
`t4-official-0.2.25/`。官方
`cubie-a7a-radxa-display-8hd.dtso` 仍采用相同 DSI0/虚拟 panel/真实 panel
拓扑，但其 `dsi0/ports/port@1` 没有 `reg`。

## 6.6 构建和离线验证

在板端使用匹配的
`/usr/src/linux-headers-6.6.98-3-aw2511` 重新预处理和编译，没有复用
5.15 DTBO。

```text
build-artifacts/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo
SHA256=31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832
```

`fdtoverlay` 与 stock 6.6 DTB 离线合并成功。合并后已验证：

- DSI0、DSI0 combo PHY、TCON0、虚拟 panel、真实 panel 均为 `okay`。
- DSI0 `port@1/reg = <1>`。
- DSI flags 保持原 v001 的 `0xa03`，即没有带入 non-burst 修改。
- 4 lanes，157 MHz，1080x2160。
- DSI endpoint 与虚拟 panel input 双向闭合：
  `db -> da`、`da -> db`。
- 虚拟 panel output 与真实 panel input 双向闭合：
  `23d -> 240`、`240 -> 23d`。
- HDMI0 仍为 `okay`，本 overlay 没有禁用 HDMI。

详细证据见：

- `build-artifacts/build.log`
- `build-artifacts/offline-merge-validation.log`
- `build-artifacts/*.readback.dts`
- `build-artifacts/*merged.dts`

`dtc` 会对官方 overlay 沿用的部分 graph 节点报告地址单元警告；它们不阻止
DTBO 生成或离线合并。合并后的真实 DSI0 `ports` 从基础 DTB 继承了正确的
`#address-cells = <1>` 和 `#size-cells = <0>`，且 `port@1/reg` 读回为 1。

## 旧驱动与 6.6 的边界

stock 6.6 没有 `sec_ts` 或 `sgm37604a` 模块；`I2C_GPIO` 和
`BACKLIGHT_PWM` 为内建。

旧 0.1.9 模块只在 `/tmp` 做了兼容性编译，没有安装。`sec_ts` 在 6.6
编译失败：

- `devm_gpiod_get_from_of_node()` 已不可用。
- `i2c_driver.probe` 的函数签名已变化。

因此本轮不强改内核驱动，先验证 DSI/显示链路。v001 中的 I2C 节点保持原样，
但在没有匹配模块时不会绑定旧 SEC/SGM 驱动。编译日志：
`build-artifacts/module-compat-build.log`。

## 已建立的启动与回滚配置

当前仅有一个 active DTBO：

```text
/boot/dtbo/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo
SHA256=31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832
```

通过 `u-boot-update` 生成配置，没有手工编辑 `extlinux.conf`：

- `l0`：加载上述 v001 DTBO。
- `l0r`：不加载任何 overlay，并保留 `single`，作为 stock 救援入口。
- 默认仍为 `l0`，U-Boot 菜单等待 10 秒。
- 启用前配置备份：
  `/boot/extlinux/backups/extlinux.conf.pre-enable-20260731-091853`。
- 启用后的本地副本：
  `build-artifacts/extlinux.enabled.conf`。

若普通入口异常：

1. 在 U-Boot 菜单选择 `l0r`。
2. 进入救援系统后执行：

```sh
sudo /usr/local/sbin/rollback-versioned-overlay-from-rescue \
  /boot/dtbo/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo
```

该脚本只把这个精确版本重命名为 `.disabled`，再运行
`u-boot-update`；不删除文件。

## 当前进度

- [x] 锁定历史候选和唯一变量。
- [x] 连接 t4 SSH 和串口。
- [x] 采集 stock 基线。
- [x] 保存 t4 官方 DTS/DTBO/基础 DTB/headers 信息。
- [x] 在 6.6 重新编译并离线合并验证。
- [x] 建立 `l0` test / `l0r` stock 双入口。
- [x] 重启后验证内核、DRM 和 SDDM 登录界面状态。
- [ ] 登录桌面后验证 DSI、HDMI、DRM 状态和致命日志计数。

## 第一次实际启动：DPMS 黑屏与唤醒结果

实际启动 boot ID：
`7a8fe62e-d15a-4392-ad59-a74c783e215a`。确认从普通 `l0` 启动并加载了
SHA256 为 `31fc84...4832` 的唯一 v001 DTBO。

启动阶段结果：

- DSI host、panel、combo PHY、TCON0 和 sunxi DRM 均完成 probe/bind。
- DSI encoder 在 8.190771 秒完成第一次 atomic enable。
- HDMI 在 13.456113 秒完成 atomic enable，PHY 状态为 `lock`。
- SDDM 在 18.451 秒为 DSI-1 创建 1080×2160 view，在 18.725 秒为 HDMI-1
  创建 1920×1080 view。
- 没有 atomic flush timeout、IOMMU PageTable Invalid、DE stale-address、RCU
  stall、NULL dereference、panic 或 soft lockup。

约 600 秒没有本地输入后，SDDM 的 X11 配置按以下定时进入 DPMS Off：

```text
Screen Saver timeout=600
DPMS Standby=600 Suspend=600 Off=600
Monitor is Off
```

618.132 秒 DE-0、DE-1 被正常 atomic-disable；采集时两个 CRTC 均为
`active=0`、connector 为 `off`、背光 `bl_power=4`。这解释了当时 HDMI 与
DSI 同时无输出，不是内核卡死。切换期间出现两次
`displl clk unable to lock`，但没有继续发展成 atomic timeout/IOMMU/RCU 故障。

在 1953 秒执行一次不落盘的 `xset dpms force on`：

- DE-0、DE-1 都恢复 `active=1`。
- DSI encoder 再次从 start 走到 finish。
- HDMI PHY 再次 lock 并恢复输出，用户现场确认 HDMI 正常。
- PWM backlight0 恢复 `bl_power=0`，PWM4 为 requested/enabled。
- 致命故障计数仍全部为 0。

但 DSI 的物理显示尚不能记为通过。原因是 stock 6.6 没有旧的魅族驱动：

- `0-0036`（SGM37604A）已由 DT 实例化，但 `driver=unbound`。
- `0-0048`（SEC touch）已由 DT 实例化，但 `driver=unbound`。
- SGM HWEN 对应 PD21 没有被请求；当前 `pwm-backlight` 只控制官方结构中的
  PWM4/PD23，并不能替代魅族屏的 SGM37604A 初始化。

因此当前结论分层为：HDMI 正常；6.6 上 v001 已完成 DSI 软件 modeset 且暂未
复现旧内核硬锁；手机屏物理出图/背光仍待现场确认和后续独立 I2C/SGM 阶段。

证据：

- `postboot-black-snapshot/`
- `after-dpms-wake.log`

## SEC 触摸与 SGM 背光驱动安装（2026-07-31）

按用户要求，本阶段不改 v001 DTBO、不切换硬件 TWI/I²C、不带入 non-burst、
reset 或 DSI-only 修改。驱动以早期已能工作的 `meizu-e3-dkms 0.1.10` 行为为
基线，只做 Linux 6.6 API 兼容：

- SEC 继续使用 `sec,irq_gpio` 与旧的 `of_get_named_gpio()` 路径；6.6 已移除的
  `devm_gpiod_get_from_of_node()` 不再调用。
- SEC/SGM 在 6.3+ 使用单参数 I²C probe 回调。
- 新 DKMS 名称为 `meizu-e3-drivers-t4/0.1.10`，避免与旧 5.15 包冲突。
- 驱动归档明确不含 overlay，安装前后
  `/boot/extlinux/extlinux.conf` 与活动 v001 DTBO 的 SHA256 校验均通过。

板端使用实际 `6.6.98-3-aw2511` headers 构建成功，两模块 vermagic 均为
`6.6.98-3-aw2511 SMP mod_unload aarch64`。源与构建材料位于
`driver-port-6.6/`，归档 SHA256 为：

```text
meizu-e3-drivers-t4-0.1.10.tar.gz
e8d8a13917b2216821c81ab806d844120af9b5355b9f67b805af5c15b4de9441
```

### 背光结果

`sgm37604a` 动态加载成功并绑定 `0-0036`，新增：

```text
/sys/class/backlight/sgm37604a
brightness=2000
actual_brightness=2000
max_brightness=4095
bl_power=0
```

当前保持加载，并通过 `/etc/modules-load.d/meizu-e3-drivers.conf` 持久加载。
加载后没有新增 Oops、RCU stall、atomic timeout 或 panic。物理亮屏效果仍以用户
现场观察为最终判断。

### 触摸探测、映射与 IRQ 风暴

SEC 动态加载时能正常完成以下步骤：

- 绑定 `0-0048`；
- 读取 ID `AC 6F 70`；
- 创建 `Samsung Electronics Touchscreen 1223`（input22/event20）；
- 申请 IRQ 107；
- 保持 FB notifier 禁用；
- 读取 IC 固件 `1.23`、TX=18、RX=32；
- X11 设备可见，`xinput map-to-output ... DSI-1` 后的矩阵为
  `0.36,0,0 / 0,1,0 / 0,0,1`，正确限制在左侧 1080×2160 DSI 区域。

但该版本在 t4 上不能安全常驻。固件 work 中软件复位后的 boot-complete 等待
超时，连续读到全零事件；随后 IRQ 启用后，PD18 一直保持 low：

```text
gpio-114 (sec,tsp_int) in lo IRQ
5 秒 IRQ 增量 = 4729，约 945 次/秒
irq/107-sec_ts CPU = 88%～90%
sched: RT throttling activated
```

再次独立测量 2 秒得到 1886 次 IRQ，排除了偶发触摸操作。持续 level-low IRQ
会长期占用一个 CPU，是明确的卡顿/锁死风险。因而已执行动态回退：

- `modprobe -r sec_ts`，负载立即恢复；
- DKMS 模块与一次性映射文件保留，便于下一版测试；
- `/etc/modprobe.d/meizu-e3-sec-ts-quarantine.conf` 设置 `blacklist sec_ts`，防止
  重启时由 DT modalias 自动加载；
- 开机模块列表暂时只保留 `sgm37604a`。

这说明触摸的 I²C 通信、设备身份和 X11 映射都已打通；当前阻塞点位于 SEC
软件复位/事件栈/IRQ 使能这一段初始化，而不是需要猜测新的 I²C 引脚或立刻切换
硬件 TWI。下一版应先验证 boot-complete、清事件栈和 sense-on 的既有驱动流程，
并加入 IRQ 速率保护；在通过空闲 IRQ 测试前不得取消 blacklist。

完整安装后安全状态快照：

```text
post-driver-install-snapshot/radxa-a733-preflash-current.tar.gz
SHA256=0f35f64b2a8aec2dc94335b34461d4acafd7986d5f583de9dcff9ae949de525a
```
