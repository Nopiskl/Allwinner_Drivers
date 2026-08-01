# Radxa A7A + 魅族 E3 手机屏双显示故障调查记录

最后更新：2026-07-31（Asia/Shanghai）

用途：保存重刷系统前已经取得的现场证据、结论、候选补丁和后续测试顺序。后续继续工作时，应先阅读本文，不要仅凭聊天上下文重新猜测。

> 本文不保存 SSH 密码。重刷后 IP、用户名、内核版本和启动配置都需要重新确认。

## 一、结论摘要

目前确认存在两个彼此独立、但外部表现容易混淆的问题。

### 1. 严重问题：A733 vendor DRM/DE 的 RCQ/page-flip 生命周期错误

在双屏启动或布局初始化过程中，DE 的 RCQ 更新可能超时。当前驱动在超时后只打印日志，仍然向上层报告 page-flip 完成，导致旧 framebuffer 被解除 IOMMU 映射；但显示硬件实际上仍在扫描旧地址，随后产生 DE0 IOMMU fault。

本次已经获得“旧帧先 unmap、DE 后访问同一旧地址”的直接证据，因此 use-after-unmap 已证实，不再只是推测。

可能表现为：

- DSI 手机屏停在旧画面、黑屏、花屏。
- 软件鼠标消失，稍后又恢复。
- HDMI 和 DSI 同时异常。
- `sunxi_de_atomic_flush timeout` 按约 52 ms 周期连续出现。
- `PageTable Invalid`、`Bug is in DE0 module`。
- IOMMU IRQ 风暴，SSH 用户态无法调度；有时 ICMP Ping 仍能回复。
- 有时 IOMMU/DE 复位后重新提交成功，画面和鼠标自行恢复。

### 2. 独立问题：SGM37604A 背光初始化和双背光持久化

背光存在两类不同现象：

- 某些启动中，SGM 初始化寄存器保持上电默认值，说明初始化写入没有生效或芯片之后复位。驱动没有回读验证、延迟重试或 reset/resume 后重初始化。
- 本次“背光很低”不是初始化失败，而是 `systemd-backlight` 正常恢复了保存的 `250/4095`，约为 6.1%。

DTSO 同时注册 `pwm-backlight` 和 `sgm37604a` 两个背光 class 设备，而且面板绑定的是 `pwm-backlight`，系统会分别保存两套亮度，后续需要统一设计。

### 3. DTS 双显示拓扑不是根因

当前硬件状态证明：

- DSI：`DE-0 -> tcon0 -> DSI-1`
- HDMI：`DE-1 -> tcon4 -> HDMI-A-1`

这是两个独立 CRTC/输出路径，不是把 DSI 与 HDMI 接到了同一个 TCON。A733 只有一个共享 DE352 硬件引擎，但提供两个输出端口；共享 DE/IOMMU 正是为什么一个 RCQ 错误可能同时影响两个屏幕。

KDE/X11 当前配置是扩展桌面：

- DSI：`1080x2160`，逻辑坐标 `(0,0)`
- HDMI：`1920x1080`，逻辑坐标 `(1080,0)`
- Xorg 总 framebuffer：`3000x2160`

一个大的 X11 framebuffer 由两个 CRTC 分别扫描不同区域，是 XRandR 扩展桌面的正常实现，不表示设备树把两路“合成一路”。

## 二、旧系统和本地代码状态

### 板端旧系统

- 内核：`5.15.147-14-a733`
- 完整 uname：`Linux radxa-cubie-a7z 5.15.147-14-a733 #14 SMP PREEMPT Mon Jan 19 10:03:49 UTC 2026 aarch64`
- 已安装：
  - `linux-image-5.15.147-14-a733 5.15.147-14`
  - `linux-headers-5.15.147-14-a733 5.15.147-14`
  - `linux-image-radxa-a733 5.15.147-14`
  - `linux-headers-radxa-a733 5.15.147-14`
- 当时板端缓存的软件源候选版本：`5.15.147-18`。未安装，也没有证明 #18 包含 BSP 1.4.8 的 RCQ 改动。
- 桌面为 KDE/X11。

### 本地工作区代码

- `radxa-allwinner-bsp`
  - 当前分支：`cubie-aiot-v1.4.6`
  - HEAD：`2045a3ca2a01f088c0314dc924bda59d154e363e`
  - 已抓取 `origin/cubie-aiot-v1.4.8`
  - v1.4.8 分支 HEAD：`f51e1e6195d4350abc590bff852e213279e660a6`
  - v1.4.8 release commit：`e1524a9`
- `radxa-allwinner-device-a733`
  - 分支：`device-a733-v1.4.6`
  - HEAD：`79d54f44e14111db3845096cef0639a6c9222707`
- `radxa-kernel-a733`
  - 分支：`allwinner-aiot-linux-5.15`
  - HEAD：`e41499895c17074874f4c48ff04041c57d8dfd99`
  - Windows checkout 因保留文件名不完整，但可以用 `git show HEAD:path` 读取文件。

### 当前本地安装包

- `meizu-e3-dkms_0.1.7_all.deb`
- 解包/构建目录：`meizu-e3-dkms_0.1.7_staging`

重要：重刷后不要原样安装 0.1.7。它包含每 2 秒执行 `xrandr --query` 的旧触摸映射脚本，应先制作安全的新版本。

## 三、0.1.7 包曾经做过的修改

### SGM37604A

- 修复了写寄存器重试路径中返回值未重新赋值的问题。
- HWEN 拉高后增加了 10 ms 等待。
- 该 10 ms 只能作为经验延时，数据手册没有保证它是“寄存器就绪的最大时间”，不能代替回读验证和延迟重试。

当前驱动仍存在的问题：

- 初始化写入后不读取 `0x10/0x11/0x1b` 验证。
- `update_status()` 只更新亮度，不会修复 mode、LED enable 和 current 寄存器。
- 芯片复位/掉电后没有可靠的重新初始化状态机。
- DTS 的 `default-brightness-level = <128>` 实际被驱动忽略；驱动内部硬编码初始亮度约 1883/2000。
- 面板并未直接绑定到 SGM backlight。

### 触摸映射

安装了：

- `/usr/lib/meizu-e3-dkms/map-touch-to-dsi.sh`
- `/etc/xdg/autostart/meizu-e3-touch-map.desktop`

旧脚本行为：

1. 每 2 秒运行一次 `xrandr --query`。
2. 每次检查触摸设备。
3. 检测到状态变化后再次运行一次 `xrandr --query`。
4. 调用 `xinput map-to-output`。

该实现不是内核 bug 的根因，但会持续触发 HDMI detect/get_modes，增加 KDE/Xorg/双 CRTC RCQ 路径负载，是不必要的风险放大器。

在最后一次旧系统启动中，已临时终止 PID 1114；没有修改永久 autostart 文件。下次重新登录仍会再次启动。

## 四、关键内核现场证据

### 1. 早先一次严重硬锁

典型日志顺序：

- 约 34.686 秒开始密集 `sunxi_de_atomic_flush timeout`，间隔约 52 ms。
- 约 42.594 秒出现 `L2 PageTable Invalid`。
- DE0 无效地址包括 `0xf897a000`、`0xf8000000`。
- 随后大量 CPU0 IRQ 上下文警告，调用点为 `sunxi_iommu_irq`。
- 系统没有正常 shutdown，日志突然结束。
- 没有 pstore。

外部状态：

- 有时仍能回复 Ping。
- SSH `/proc/uptime` 都无法运行，符合 IRQ 风暴导致用户态饥饿。
- 最后只能物理断电。

### 2. 最后一次干净冷启动中的可恢复复现

boot ID：

`334bdfc8-a47b-4b2c-b354-15e9d6cb0dbb`

事件：

- 8.714 秒：启动阶段已有一次 `sunxi_de_atomic_flush timeout`。
- 39.340–45.246 秒：连续 108 次 `sunxi_de_atomic_flush timeout`。
- 45.291 秒起：3 次页表错误。
- 45.301、45.325、45.350 秒：DE0 访问无效地址 `0xfa000000`。
- 45.366 秒：`--- SUNXI DRM DEBUG ---`。
- 同一份 debug dump 同时记录 DE-0 和 DE-1。

计数：

```text
flush=108
page_table=3
de_fault=3
touch_unknown=0
```

### 3. use-after-unmap 直接证据

DE0 debug frame 记录：

| 时间（秒） | 记录 |
|---|---|
| 45.088696562 | 旧帧 `0xfa000000` 被提交 |
| 45.192134770 | 新帧 `0xfc000000` 为 `map:1, unmap-ts:0` |
| 45.193001228 | 旧帧 `0xfa000000` 变为 `map:0` |
| 45.301344 | DE0 仍访问 `0xfa000000` 并触发 fault |

旧帧解除映射约 108 ms 后，DE0 仍读取它。

DRM debug dump 中循环出现的 Xorg framebuffer：

- `0xf4000000`
- `0xf8000000`
- `0xfa000000`
- 最后有效的 `0xfc000000`

它们都是：

- 格式：XR24
- 大小：`3000x2160`
- pitch：12000

故障后的 DRM 原子状态：

- DE0/DSI 和 DE1/HDMI 都引用 framebuffer 167。
- 唯一有效物理地址：`0xfc000000`。

稍后屏幕和鼠标自行恢复时：

- DE0/DE1 仍使用 `0xfc000000`。
- DE0 `last rcq at vsync` 从约 2114 推进到 28657。
- DE1 `last rcq at vsync` 从约 2064 推进到 28703。

这证明 IOMMU/DE 故障处理后，后续 RCQ 提交有时能够重新成功。

## 五、源码级故障链条

### 已证实的上层安全错误

`drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c`：

- `sunxi_de_atomic_flush()` 对 RCQ 使用 `read_poll_timeout()`。
- 每 2 ms 检查一次，最多等待 50 ms。
- 超时后仅打印 `sunxi_de_atomic_flush timeout`。
- 函数返回类型为 `void`，无法把失败传递给上层。

`drivers/drm/sunxi_drm_crtc.c`：

- 调用 `sunxi_de_atomic_flush()`。
- 随后不判断是否超时，无条件调用 `sunxi_crtc_finish_page_flip()`。
- 用户态/DRM core 因此认为当前帧已经安全显示，可以释放旧 framebuffer。

这与实测的“旧帧 unmap 后仍被 DE 访问”完全一致。

官方源码：

- [v1.4.6 sunxi_de_atomic_flush](https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.6/drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c#L689-L785)
- [v1.4.6 CRTC 无条件 finish page flip](https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.6/drivers/drm/sunxi_drm_crtc.c#L2030-L2040)
- [DRM debug frame map/unmap 记录实现](https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.6/drivers/drm/sunxi_drm_debug.c#L99-L126)
- [IOMMU fault handler](https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.6/drivers/iommu/sunxi-iommu-v2.c#L1246-L1419)

### 最强的 RCQ 超时原因候选

v1.4.6 在每次 RCQ flush 中执行：

```c
de_top_update_force_by_ahb(engine->top_hdl);
```

DE top 是两个输出共享的 singleton，`de_top_create()` 对 `id > 0` 直接拒绝创建第二个实例。`de_top_update_force_by_ahb()` 操作共享的 `reg_blks[0]`。

官方 BSP v1.4.8 把这行注释掉：

```c
// de_top_update_force_by_ahb(engine->top_hdl);
```

这正处在本次失败路径中，是目前最强的补丁候选。

但必须保持准确：

- 官方提交说明没有明确写“修复 A733 双屏 RCQ”。
- 尚未在用户的新镜像/内核上完成 A/B 测试。
- 因此不能宣称 v1.4.8 已确定修复。

参考：

- [v1.4.8 release commit](https://github.com/radxa/allwinner-bsp/commit/e1524a9)
- [v1.4.8 sunxi_de.c](https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.8/drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c#L695-L791)

### 第二个源码风险点，尚未证实

`de_rtmx_init_rcq()` 会把共享的 DE top / writeback register block 放入每个显示的 RCQ header。

每个 `struct de_reg_block` 只有一个 `rcq_hd` 指针；初始化第二路显示时可能覆盖第一路保存的 header 指针，之后清 dirty 状态可能作用于错误的显示 header。

这个结构问题在 v1.4.8 中仍然存在。目前没有现场证据证明它就是本次直接原因，只应列为后续调试候选。

## 六、设备树和显示拓扑调查

官方 A733 DTS 表明：

- DE 版本：v352。
- 一个 DE 硬件模块提供 disp0/disp1 两个输出 port。
- DSI0 通过 dlcd0/tcon0。
- HDMI0 通过 tv0/tcon 路径。
- DE 是 IOMMU master id 8，名称为 `DE0`。

旧系统实时 DRM 状态：

```text
DSI-1    -> DE-0 -> tcon0 -> 1080x2160
HDMI-A-1 -> DE-1 -> tcon4 -> 1920x1080
```

因此：

- 不需要额外 DTS 节点才能把 HDMI 和手机屏作为两个显示器。
- 当前双屏崩溃不是因为 DSI/HDMI 被错误接到同一 TCON。
- 如果需要两个完全隔离的 X session/multiseat，那是 Xorg/登录会话配置，不是设备树配置。

参考：

- [A733 SoC DTS 显示节点](https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.6/configs/linux-5.15/sun60iw2p1.dtsi#L3720-L3806)
- [Cubie A7A board DTS](https://github.com/radxa/allwinner-device/blob/device-a733-v1.4.6/configs/cubie_a7a/linux-5.15/board.dts#L1721-L1834)

## 七、背光调查细节

### 当前正常初始化但低亮度的寄存器

最后一次旧系统启动中读取到：

```text
0x10=0x07   LED1 + LED2 + DEV_EN
0x11=0x05   I2C-only brightness mode
0x19=0x0f   brightness MSB
0x1a=0xfa   brightness LSB/reserved bits
0x1b=0x00   current setting
0x1f=0x00   no hardware fault
```

`0x19:0x1a` 对应 brightness 250。

sysfs：

```text
/sys/class/backlight/backlight0:
  brightness=73
  actual_brightness=73
  max_brightness=255

/sys/class/backlight/sgm37604a:
  brightness=250
  actual_brightness=250
  max_brightness=4095
```

持久化文件：

```text
/var/lib/systemd/backlight/platform-backlight0:backlight:backlight0
73

/var/lib/systemd/backlight/platform-gpio-i2c0:backlight:sgm37604a
250
```

本次低亮度是 `systemd-backlight` 正常恢复 250，约为 6.1%。

### 早先完全不亮时的寄存器

曾经反复读到：

```text
0x10=0x1f
0x11=0x65
0x19=0x0f
0x1a=0xfa
0x1b=0x00
0x1f=0x00
```

其中：

- `0x10=0x1f` 是 enable 寄存器上电默认值，不是期望的 `0x07`。
- `0x11=0x65` 是 I2C × PWM 默认模式，不是期望的 I2C-only `0x05`。
- fault 为 0，说明不是 LED open/short/过温/过流/过压。

这说明驱动后续的亮度写入可以成功，但 mode/enable 初始化没有生效或芯片中途复位。sysfs 仍显示 brightness 250，因此 sysfs 缓存不能证明芯片工作模式正确。

### 为什么会出现“突然亮一下，然后很暗”

驱动初始化时先写约 1883 的亮度，注册 backlight 时又硬编码 brightness 2000；稍后 `systemd-backlight` 恢复保存值 250。

因此正常启动也可能出现：

```text
初始化较亮 -> systemd 恢复 250 -> 突然变暗
```

若 mode 初始化失败而保持 `0x65`，有效亮度还会受到 PWM 73/255 相乘影响：

```text
250/4095 × 73/255 ≈ 1.75%
```

这可能暗到看起来像没有背光。

### DTSO 背光结构

当前 overlay：

- 创建 `backlight0`，compatible 为 `pwm-backlight`。
- `backlight0` 使用 PWM0 channel 4、25,000 ns、反相，enable GPIO PD23。
- DSI panel 的 `backlight = <&backlight0>`。
- 另建 `sgm37604a@36`，HWEN GPIO PD21。
- SGM 和 SEC touch 共用 GPIO bit-banged I2C bus 0。

后续应先确认手机主板实际布线，再决定：

- 面板是否应直接绑定 SGM backlight；
- 是否仍需 PWM 输入和 PD23 gate；
- SGM 应使用 I2C-only 还是 I2C × PWM；
- 如何只向 KDE/systemd 暴露一个逻辑亮度控制。

SGM 官方资料：

- [SGM37604A datasheet](https://www.sg-micro.com/rect/assets/1f66017e-4812-4ca8-bead-8b30d6abce5b/SGM37604A.pdf)

## 八、触摸与鼠标调查

触摸设备：

```text
Samsung Electronics Touchscreen 1223
I2C address 0x48
max coords 1080x2160
input event19（旧系统最后一次启动）
```

本次启动：

- 启动阶段出现过一次 `sec_ts_wait_for_ready: Time Over`。
- 随后 firmware/version 检查完成，probe 成功。
- 本次可恢复 RCQ 故障期间 `touch_unknown=0`。

另一次已经损坏的启动中曾连续读取 `ff ff ff ff ff ff` unknown event，但它发生在系统/显示已经异常的时间段，不能证明触摸芯片是 DE fault 的根因。

鼠标消失的解释：

- DRM 原子状态没有启用独立 cursor plane。
- Xorg 使用共享 framebuffer 中的软件光标。
- DSI 停在旧 framebuffer 时，用户态即使继续绘制光标，手机屏也看不到更新。
- DE 后续成功切到当前有效 framebuffer 后，鼠标重新出现。

## 九、对 `xrandr` 轮询的准确判断

已经观察到：

- 旧映射脚本 PID 1114 正在运行。
- 每 2 秒执行 `xrandr --query`。
- HDMI detect 日志按相同时序持续增加。
- 某些硬锁前存在密集 HDMI detect/EDID 操作。

应保持准确：

- 轮询是高度相关的触发器/放大器。
- 普通 KDE/KScreen 启动和正常 page-flip 也已经足以走到相同内核路径。
- 不能把内核 use-after-unmap 归咎于用户态脚本；内核不应因为合法 connector query/page-flip 而释放仍被硬件使用的内存。
- 即使新内核修复，也不应保留每 2 秒轮询设计。

新版本应采用：

- 固定布局时的一次性 Coordinate Transformation Matrix；或
- KDE/X11 输出变化事件驱动；或
- 登录后延迟一次 `xinput map-to-output`，不循环探测。

## 十、重刷最新镜像后的测试顺序

必须分阶段，避免一开始同时恢复所有旧配置后无法判断是哪一层。

### 阶段 0：不要恢复旧包

- 不要原样安装 `meizu-e3-dkms_0.1.7_all.deb`。
- 不要恢复旧 `/boot`。
- 不要恢复旧 KScreen/autostart。
- 先只接 HDMI 启动官方镜像。

### 阶段 1：官方镜像基线

记录：

- `uname -a`
- `cat /proc/cmdline`
- `/etc/radxa_image_fingerprint`
- `/etc/radxa_apt_snapshot`
- 已安装 kernel image/headers 包
- AW BSP version
- DRM/IOMMU 启动日志
- 官方镜像是否自带 v1.4.8 或更新代码

至少静置 5–10 分钟，确认 stock HDMI 不产生：

- `sunxi_de_atomic_flush timeout`
- `PageTable Invalid`
- `Bug is in DE`

### 阶段 2：只启用 DSI panel，不启用旧触摸轮询

- 针对新内核重新编译 DKMS。
- 先只加载 DSI panel/backlight。
- 确认 overlay 的 phandle、regulator、TCON 名称与新镜像 DTS 一致。
- 冷启动多次。
- 读取 SGM 寄存器，验证每次都是期望值。

### 阶段 3：加入触摸

- 加载 SEC touch 驱动。
- 不安装循环 `xrandr` 脚本。
- 先验证触摸原始坐标和事件稳定性。
- 再做一次性/事件驱动映射。

### 阶段 4：启用双屏扩展桌面

测试矩阵：

- 冷启动，HDMI 开机前已连接。
- 冷启动，不连接 HDMI。
- KDE 登录后再连接 HDMI。
- 正常 HDMI 拔插。
- DSI 主屏、HDMI 副屏。
- 固定扩展布局运行至少 30 分钟。

每个阶段监控：

```text
sunxi_de_atomic_flush timeout
PageTable Invalid
Bug is in DE
SUNXI DRM DEBUG
DE-0 exception
DE-1 exception
sunxi_iommu_irq
```

### 阶段 5：若新内核仍复现

优先 A/B 测试：

1. 保留官方原始内核作为回退项。
2. 复制相同源码/config 构建测试内核。
3. 仅删除 `de_top_update_force_by_ahb()` 调用。
4. 重复相同双屏测试矩阵。
5. 若仍失败，再增加 RCQ timeout 安全处理，禁止在未完成时报告 page-flip 完成/释放旧 framebuffer。

不要直接覆盖唯一可启动内核；必须保留可选回退项。

## 十一、重刷后预计制作的新包

建议新版本命名为 0.1.8 或更高，至少包含：

- 针对新内核 headers 重新编译。
- 删除 2 秒 `xrandr` 轮询。
- 触摸映射改为一次性或事件驱动。
- SGM 初始化寄存器写后回读。
- 回读不匹配时进行有上限的延迟重试。
- resume/reset 后重新验证完整状态。
- 驱动返回实际 I2C 错误，不再始终向 backlight core 返回成功。
- 明确一个逻辑背光设备，避免 PWM/SGM 分别被 KDE/systemd 保存。
- 可选 debug 日志，打印实际 mode/enable/brightness/fault 寄存器。

## 十二、本地诊断工具

这些脚本保存在工作区，重刷后可选择性上传。它们不调用 `xrandr`：

- `remote-postmortem-display.sh`
  - 读取上一次 boot 的显示故障时间线。
- `remote-safe-display-state.sh`
  - 读取 backlight、SGM、DRM atomic state、KScreen 配置。
- `remote-extract-drm-debug.sh`
  - 提取 SUNXI DRM DEBUG 帧记录。
- `remote-read-sgm37604a.sh`
  - 强制只读 SGM 六个寄存器；使用 `i2cget -f`，仅应在必要时短时运行。
- `remote-read-backlight-persistence.sh`
  - 读取 systemd-backlight 保存值。
- `remote-kernel-version-check.sh`
  - 读取内核、包候选和源码引用。
- `remote-count-display-faults.sh`
  - 统计当前 boot 的 RCQ/IOMMU fault。
- `remote-compare-recovered-state.sh`
  - 比较恢复后的 framebuffer 和 RCQ 进度。

注意：

- `/sys/class/drm/*/status` 在该内核中只读取缓存状态，不主动 detect。
- `xrandr --query` 会走 DRM connector probe/get_modes/EDID 路径。
- 调试初期仍应避免任何不必要的 `xrandr`。

## 十三、后续工作中的判断原则

- 静态 DTS 错误通常稳定复现；本次概率性差异更符合启动时序竞争。
- “屏幕不亮”必须先区分：
  - 用强光能看到图像：背光问题。
  - 背光存在但画面黑/花/冻结：DSI/DE/RCQ 问题。
- sysfs brightness 是驱动缓存，不能证明 SGM mode/enable 寄存器正确。
- 单次启动成功不能证明修复；至少需要多次冷启动、双屏、热插拔和持续运行。
- 新镜像是否修复必须以 `atomic_flush timeout`、IOMMU fault 和 DRM map/unmap 为准，不能只看“此刻能亮”。

## 十四、重刷后最新官方镜像基线（2026-07-31）

### 连接和镜像身份

- 新系统地址仍为 `192.168.0.107`。
- 主机名：`radxa-cubie-a7a`。
- 重刷清除了旧 `authorized_keys`，原 Windows 私钥暂时不能登录。
- 新 SSH ED25519 host key 指纹：
  - `SHA256:5jqKSr5Xe+QbPcbTamTyFd1kaHFt1ffeXs5W2sJ9qvo`
- 新 host key 已单独固定在本地：
  - `radxa-reflash-known-hosts`
- 本文仍不保存登录密码。

镜像：

```text
Debian GNU/Linux 11 (bullseye)
RSDK_BUILD_DATE='Thu, 30 Apr 2026 16:56:20 +0000'
```

内核：

```text
Linux radxa-cubie-a7a 5.15.147-21-a733
#21 SMP PREEMPT Thu Apr 30 12:14:04 UTC 2026
AW BSP version: 18dcb68d3d, 2026-04-30 12:13:15, RadxaOS SDK
```

已安装并匹配：

```text
linux-image-5.15.147-21-a733    5.15.147-21
linux-headers-5.15.147-21-a733  5.15.147-21
linux-image-radxa-a733           5.15.147-21
linux-headers-radxa-a733         5.15.147-21
```

headers 路径：

`/usr/src/linux-headers-5.15.147-21-a733`

因此新内核具备重新编译 Meizu DKMS 模块的条件。

### 干净系统状态

- 没有安装 `meizu-e3` 包。
- 没有加载 `sec_ts` 或 `sgm37604a`。
- 当前没有 backlight class 设备。
- 当前只有 stock HDMI：
  - `HDMI-A-1 -> DE-0`
  - `1920x1080@60`
  - framebuffer 物理地址 `0xfa000000`
  - DE-1 关闭
- 没有 DSI connector，因为尚未应用 Meizu overlay。

在约 18 分钟的 stock 单 HDMI 基线中：

```text
sunxi_de_atomic_flush timeout=0
PageTable Invalid=0
Bug is in DE=0
SUNXI DRM DEBUG=0
sunxi_iommu_irq=0
```

结论：#21 在单 HDMI、单 CRTC 条件下基线正常。该结果不能证明双 CRTC bug 已修复。

### #21 是否包含 BSP 1.4.8 RCQ 候选修复

headers 没有携带完整 DRM C 源码，因此直接对 `/boot/vmlinuz-5.15.147-21-a733` 做 ARM64 反汇编。

System.map：

```text
ffff8000088e7894 T sunxi_de_atomic_flush
ffff8000088e94b0 T de_top_update_force_by_ahb
```

在 `sunxi_de_atomic_flush` 内部找到：

```text
ffff8000088e7ab0: ldr x0, [x22, #136]
ffff8000088e7ab4: bl  ffff8000088e94b0
```

`ffff8000088e94b0` 正是 `de_top_update_force_by_ahb`。

结论：最新 #21 内核仍在每次相应 RCQ flush 中调用 `de_top_update_force_by_ahb()`，没有包含官方 BSP 1.4.8 中注释掉该调用的改动。

另外，#21 的 DRM state 输出仍是 v1.4.6 风格，没有 v1.4.8 增加的 `offline:` 状态字段，与二进制结论一致。

因此：

- 重刷最新镜像提供了干净基线和更新内核，但不能仅凭版本号认为旧双屏 RCQ 风险已消失。
- 下一步仍应先针对 #21 重编 DKMS/overlay，再做受控双屏测试。
- 若 #21 双屏复现相同 timeout/IOMMU fault，首个内核 A/B 补丁仍是删除该 `de_top_update_force_by_ahb()` 调用。

### #21 镜像的 overlay/DTB 机制

新镜像已经弃用：

- `/boot/uEnv.txt`
- `/boot/hw_intfc.conf`

两个文件都明确提示使用 `rsetup` 管理 overlay。`/boot/extlinux/extlinux.conf` 也由 `u-boot-update` 自动生成，不应手工编辑。

当前安装：

```text
radxa-overlays-dkms 0.2.18
rsetup              0.4.27
```

overlay 目录：

`/boot/dtbo`

内核 DTB 目录：

`/usr/lib/linux-image-5.15.147-21-a733/`

实时设备树：

```text
model=sun60iw2
compatible=radxa,cubie-a7a
           arm,sun60iw2p1
           allwinner,sun60i-a733
```

现有 Meizu overlay 的 `compatible = "radxa,cubie-a7a"` 仍然匹配新镜像。但安装/启用流程必须适配 `rsetup`/`/boot/dtbo`，不能直接照搬旧镜像的 boot 配置修改方式。

## 十五、Radxa 官方 A7A DSI overlay 对比（2026-07-31）

已克隆官方仓库：

```text
https://github.com/radxa-pkg/radxa-overlays.git
local: radxa-overlays-official
HEAD: c79b70822a314a7c828d361cbe976780af45c0a3
tag: 0.2.28
```

重点源文件：

- `cubie-a7a-radxa-display-8hd.dtso`
- `cubie-a7a-radxa-display-10fhd.dtso`
- 当前 `cubie-a7a-meizu-e3-display.dtso`

官方 A7A 8HD/10FHD 与 Meizu E3 共有的框架：

- 都启用 `dlcd0`、`dsi0`、`dsi0combophy`。
- 都使用 4-lane、RGB888、`allwinner,panel-dsi` 和 `allwinner,virtual-panel`。
- PWM 背光均为 PWM0 channel 4、周期 25000 ns、反相，enable GPIO 为 PD23，默认等级 73。
- DSI graph 的总体拓扑相同。
- 官方 overlay 没有禁用 HDMI。

关键差异：

1. 官方当前版本在 `dsi0_out: port@1` 中有 `reg = <1>`；Meizu overlay 缺失该属性。
2. Radxa 于提交 `4349013e00f21b703a75d620d8589f301ffc0493` 专门修复该缺失，提交说明是它会导致 DRM component framework 的 OF graph resolution failure。该修复在 `0.2.18` 之后，当前官方 `0.2.28` 已包含。
3. 官方只使用 `MIPI_DSI_MODE_VIDEO`；Meizu 使用 `VIDEO | VIDEO_BURST | LPM | NO_EOT_PACKET`。在当前 BSP 中，BURST 会进入独立寄存器配置路径，并把 DSI 像素/HS 时钟再乘 `10/9`。
4. 官方 8HD/10FHD 都使用 70 MHz pixel clock，约 420 Mbit/s/lane；Meizu 使用 157 MHz，原始约 942 Mbit/s/lane，BURST 路径后的 HS rate 约 1046.7 Mbit/s/lane。Meizu 链路负载约为官方的 2.49 倍。
5. 官方供电等待 10 ms、复位等待 20 ms；Meizu 分别为 120 ms，并额外有 120 ms enable delay。
6. 官方面板 reset 是 PD21，触摸 reset 是 PD19；Meizu 硬件接法相反：PD19 是面板 reset，PD21 是 SGM37604A HWEN。这部分不能直接照抄官方引脚。
7. 官方触摸通过原生 `twi2` 400 kHz 工作，配置了 pinctrl、上拉、`twi_drv_used = 1`、`no_suspend = 1` 和供电；Meizu 因 SEC 触摸与 SGM 背光芯片共线，当前使用 `i2c-gpio` bit-bang，延时 2 us。
8. 官方只有一个由 panel 引用的 PWM backlight；Meizu 同时有 PWM backlight 和 SGM37604A backlight class。两个亮度控制路径若状态不同步，可解释“sysfs 亮度值正常但实际亮度异常”，但不解释全机 RCU stall。

与现象的关联：

- 缺失 `port@1/reg` 是已经被 Radxa 官方确认并修复的图解析错误，应无条件移植。
- 官方没有“只禁用 hdmi0”的 overlay。此前的 DSI-only debug overlay 只关闭 HDMI 一部分组件，会留下不完整的 HDMI component/extcon 拓扑，不应继续使用。
- Meizu 的高 DSI 时钟与 BURST 专用路径比官方测试配置激进得多，是黑屏、FIFO/时序异常和显示提交卡住的高优先级 A/B 对象。
- 但屏幕原生 1080x2160 时序、PD19/PD21 分工、SEC/SGM 驱动不能直接替换为官方屏参数。正确做法是保留手机屏硬件必需项，只逐项移植官方的 graph 修复和保守的软件拓扑。

建议的下一轮受控顺序：

1. 删除临时 DSI-only overlay，先保持 HDMI 拓扑完整。
2. 给 Meizu overlay 补 `dsi0_out/port@1/reg = <1>`。
3. 保留 Meizu 分辨率、复位引脚、SEC/SGM 驱动，先测试主 overlay 单独启用。
4. 再分别 A/B `NO_EOT_PACKET`、`LPM`、`VIDEO_BURST`，一次只改一个变量。
5. 每个候选至少做多次冷启动，同时通过串口统计 RCU stall、DRM atomic flush timeout、IOMMU fault 和 DSI FIFO/IRQ。

## 十六、禁用 overlay 后的 `load_module/kobject_get` panic

用户离线执行了：

- 将 Meizu 主 DTBO 和 DSI-only debug DTBO 重命名为 `.off`。
- 删除 `extlinux.conf` 中全部 `fdtoverlays` 行。
- 同步、卸载并尝试让 USB 块设备断电。

随后 stock DTB 启动在约 10.25 秒出现：

```text
Unable to handle kernel NULL pointer dereference at 0x0000000000000cfc
pc : kobject_get+0x18/0xac
lr : kobject_add_internal+0x38/0x2c0
load_module+0x2060/0x2a50
PID 494 Comm: modprobe
ecb(+)
```

寄存器 `x0 = 0xcc0`，故 `kobject_get()` 读取该伪对象内部偏移后访问 `0xcfc`。在该内核源码中，`mod_sysfs_init()` 在模块加载时先清零 `mod->mkobj.kobj`，然后调用 `kobject_init_and_add()`；正常的 parent 不可能是 `0xcc0`。这说明在 `ecb` 模块注册 sysfs 对象时，其 kobject 字段或相邻内存已经损坏。

同一时刻另一个线程在 `aic btusb_shutdown` 中访问了未映射的内核地址。模块列表中存在厂商树外模块 `aic8800_fdrv(O)`、`aic_btusb(O)`，但没有 `sec_ts` 或 `sgm37604a`。

因此：

- 这不是新增 `dsi0_out/port@1/reg = <1>` 直接触发的崩溃；此次启动根本没有应用 Meizu overlay。
- DTBO 重命名和删除 `fdtoverlays` 本身不会修改内核模块、module kobject 或内核内存。
- 第一段命令中 `udisksctl power-off -b RADXA_MNT=/media/nopiskl/rootfs` 参数错误，不会让 `/dev/sdb` 断电。若当时 `unmount` 也失败后直接拔盘，存在文件系统或 `ecb.ko` 损坏的可能。
- 若文件系统和内核包校验完全正常，则优先怀疑 stock #21 内核或 AIC Wi-Fi/蓝牙树外驱动造成的先期内存破坏；物理内存/供电不稳是次一级候选。

在再次启用显示前，先完成：

1. 对未挂载的 `/dev/sdb3` 运行只读 `e2fsck -fn`。
2. 校验 `linux-image-5.15.147-21-a733` 包内文件，尤其是 `crypto/ecb.ko*`。
3. 确认正在启动的 kernel、initrd 和 `/lib/modules/5.15.147-21-a733` 完全配套。
4. 若文件无损且 stock 启动仍能复现，再用启动参数临时屏蔽 AIC Wi-Fi/蓝牙模块做 A/B。

### 离线文件系统和包校验结果

对未挂载 `/dev/sdb3` 执行 `e2fsck -fn`：

```text
第 1～5 遍均完成
rootfs：146558/1921984 文件，1372661/7706747 块
```

没有报告 inode、目录、块位图或 journal 错误，因此 ext4 损坏假设基本排除。

`linux-image-5.15.147-21-a733` 的 md5 校验显示：

- `lib/modules/5.15.147-21-a733/kernel/crypto/ecb.ko.xz`：成功。
- `boot/vmlinuz-5.15.147-21-a733`：失败。
- `modules.alias*`、`modules.dep*`、`modules.symbols*` 共 6 个 depmod 生成文件：失败。

6 个 module 索引在 DKMS 模块安装/卸载并执行 `depmod` 后变化是正常现象，不能据此认定损坏。`ecb.ko.xz` 与发行包一致，排除了 panic 是由磁盘上损坏的 `ecb` 文件直接导致。

`vmlinuz` 内容不匹配需要继续判断是 Radxa 镜像安装流程的既有变更，还是运行内核曾被替换。还需校验其实际/包内 md5、时间和版本字符串。

同时，panic 时存在但不属于该 `linux-image` 包校验范围的 AIC 树外模块仍是重要对象：

- `aic8800_fdrv(O)`
- `aic_btusb(O)`
- `aic_load_fw(O)`

下一步应定位这些 `.ko*` 的文件路径、DKMS/软件包来源和 vermagic；若 kernel/module 配套无误，stock 启动时临时屏蔽 AIC 三个模块是最有信息量的 A/B。

## 十七、重刷后的后续工作约束

用户要求后续：

1. 模仿 Radxa 官方仓库中经过测试的 A7A DSI 屏 overlay 进行 DTSO 适配，不猜测参数，不以修改内核驱动替代正确的设备树适配。
2. 使用合理、可验证、可动态切换和可回退的修改方式；测试 DTSO 出错时应能切回 stock 配置并重启，避免再次拆盘救援。
3. 持续把发现、配置、产物哈希和完整日志保存到当前 workplace，避免因上下文增长遗失。

具体流程已固化在 `RADXA_A7A_WORKING_RULES.md`。后续所有板端写操作必须服从该规范。

## 十八、v001 首次受控启动现场（2026-07-31）

### 部署与回滚状态

- `meizu-e3-dkms 0.1.9` 已针对当前 `5.15.147-21-a733` 内核完成
  DKMS 编译和安装。
- 安装到 `/boot/dtbo` 的 DTBO 与离线通过 `fdtoverlay` 验证的产物
  逐字节一致，SHA256 为
  `31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832`。
- 使用 rsetup 的官方底层机制（`.disabled` 改为 `.dtbo` 后执行
  `u-boot-update`）启用，没有手工编辑生成的 `extlinux.conf`。
- 默认 `l0` 只加载
  `/boot/dtbo/cubie-a7a-meizu-e3-display-v001.dtbo`。
- `l0r` 救援项没有 `fdtoverlays`，仍是 stock DTB；启用前的
  `extlinux.conf` 已保存到 `/boot/extlinux/backups/`。

完整安装和启用输出位于：

- `test_files/mainline/01_initial_overlay_validation/log/install-0.1.9.txt`
- `test_files/mainline/01_initial_overlay_validation/log/enable-v001.txt`

### 首次启动的准确可见现象

1. LightDM 登录界面在 HDMI 和 Meizu DSI 屏上都能正常显示。
2. 用户进入桌面会话后，HDMI 变成纯蓝色，Meizu DSI 屏变成灰白色。
3. 因用户当时不在设备旁边、较晚登录，SSH 较晚出现不能作为内核启动
   阻塞证据；这条时间证据已排除。
4. 桌面异常后 `192.168.0.103` 无 ARP/ICMP/SSH。若 Wi-Fi 连接属于
   用户会话，此现象本身也不能单独证明内核硬锁，仍需串口或下次启动的
   persistent journal 判定。

### 串口确认后的结论

- 登录界面能正常显示，证明 v001 DTBO 已被 U-Boot 应用，DRM component
  能完成绑定，面板供电/复位/DSI 初始化至少在该次启动成功；这不是
  `port@1/reg` 缺失或 DTBO 完全未应用的表现。
- 故障严格发生在桌面会话启动后的第二次显示配置/原子 modeset，优先调查
  Xorg/Xfce 显示配置触发的双 CRTC RCQ/DE/IOMMU 路径。
- 已从本机 CH340 `COM4` 只读抓取 35 秒现场串口，保存为
  `test_files/mainline/01_initial_overlay_validation/log/postboot-v001-serial-live.txt`。
- 抓取区间为内核时间 454.13–489.08 秒，共记录 1402 轮完全相同的
  IOMMU fault，约 40.1 轮/秒：

```text
L1 PageTable Invalid
0x0x00000000fa000000 is not mapped!
Bug is in DE0 module, invalid address: 0xfa000000, data:0x0, id:0x4
exception had already record !
```

- 内核时间 476.131 秒又出现
  `rcu_preempt detected expedited stalls on CPUs/tasks`。也就是说高频
  DE0 IOMMU fault 已经使系统进入 RCU stall，能够解释网络失联和心跳异常。
- 地址 `0xfa000000` 与旧系统的已证实故障逐字一致。旧现场曾完整记录：
  旧帧 `0xfa000000` 被提交，随后变为 `map:0`，但 DE0 仍继续扫描该地址并
  触发 fault。因此最新 #21 内核仍复现同一个
  `stale framebuffer/use-after-unmap` 故障，而不是一个新的背光或触摸问题。
- 本次串口抓取开始时 fault 已持续发生，未包含首次 fault 前后的
  `SUNXI DRM DEBUG` map/unmap 记录；应在 stock rescue 启动后继续提取
  persistent journal，若 journal 尚未落盘则下一轮必须从开机起持续抓串口。
- 曾尝试通过串口依次发送 Magic SysRq `s`、`u`、`b`，希望同步文件系统、
  只读重新挂载并重启；在持续的 DE0 fault/中断风暴中内核没有处理这些
  SysRq，串口仍只输出相同 fault。因此当前需要物理 reset/重新上电，并在
  U-Boot 菜单选择 `2` 进入不加载 overlay 的 `l0r`。
- 在提取 `journalctl -b -1` 或下一轮首次 fault 前后的完整串口证据前，
  不改面板时序、DSI flags、GPIO 或内核驱动，也不新增 DSI-only overlay。

### l0r 回滚及 persistent journal

用户物理重启并选择 U-Boot 菜单 `2` 后，串口确认：

```text
/proc/cmdline: ... single
active DTBO file: cubie-a7a-meizu-e3-display-v001.dtbo
loaded Meizu modules: none
```

即 `l0r` 确实没有加载 active overlay。随后在 root rescue shell 中：

1. 备份启用状态的 `extlinux.conf` 到 `/boot/extlinux/backups/`。
2. 将 v001 从 `.dtbo` 改回 `.dtbo.disabled`。
3. 运行官方 `u-boot-update`。
4. 验证 `/boot/dtbo` 中 active `.dtbo` 数为 0，生成的 `l0`/`l0r`
   均无 `fdtoverlays`。
5. 验证禁用后的 DTBO SHA256 仍为
   `31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832`。

回滚记录位于
`test_files/mainline/01_initial_overlay_validation/log/rollback-v001-from-l0r.txt`。

从 persistent journal 取得了完整的故障起点：

| 内核时间 | 事件 |
|---:|---|
| 109.846 s | `wlan0` link ready（对应用户登录/网络建立阶段） |
| 110.982、112.400 s | HDMI EDID/mode 查询 |
| 112.923 s | 第一个 `sunxi_de_atomic_flush timeout` |
| 112.923–119.389 s | 已捕获 116 次 atomic flush timeout |
| 119.503 s | 第一个 IOMMU fault：L2 invalid，地址 `0xfae77000` |
| 119.527 s | 紧接着 L1 invalid，地址 `0xfa000000` |

首个 fault 的 warning 位于 `sunxi_iommu_irq+0x294/0x59c`，CPU0 IRQ
上下文。日志明确列出 `sec_ts`、`sgm37604a` 已加载，但两者不在调用栈；
调用栈完全处于 IOMMU IRQ 处理路径。因 fault 后 journal 被高频重复
warning 填满，仅串口保存前 573 KB，已足以覆盖首次 timeout、首次 fault
和完整调用栈。

关键文件：

- `failed-v001-journal-kernel.txt`
- `postboot-v001-serial-live.txt`

### 软件 reboot 的独立异常

回滚后在 stock rescue 中执行了正常 `sync` 和 `systemctl reboot`。systemd
完整停止服务、卸载文件系统，并输出：

```text
reboot: Restarting system
```

但之后超过 70 秒没有新的 U-Boot/BootROM 串口输出。这说明该次 vendor
平台的软件 reset 没有真正重启 SoC，需要物理 reset/重新上电；它发生在
overlay 已禁用且 rescue 内核未加载 Meizu 模块的状态，不能归因于 DTBO。

## 十九、v002 非 burst 单变量实验（2026-07-31）

在 stock HDMI-only Plasma 登录后稳定、当前显示故障计数为 0 的基础上，制作
`meizu-e3-dkms 0.1.10`。v002 只删除
`MIPI_DSI_MODE_VIDEO_BURST`，保留 v001 的全部面板时序、供电、复位、背光、
触摸、HDMI 和图连接，并保留 Radxa 官方提交
`4349013e00f21b703a75d620d8589f301ffc0493` 的
`dsi0/port@1/reg = <1>` 修复。没有修改内核或驱动。

板端离线编译、`fdtoverlay` 合并和读回均成功：

- v002 DTBO SHA256：
  `b05d2220b31452a46ffb83940f349d1827be0d4c8e352f36b9e04fb9b0db3be2`
- `dsi,flags` 从 v001 的 `0x0a03` 变为 `0x0a01`
- 四 lane、RGB888、1080x2160、157 MHz 和全部 porch/sync 数值不变
- DSI0 的 `port@1/reg = 1`，两段 endpoint 均双向闭合
- DSI0、DSI PHY 和 HDMI0 均为 `okay`
- v001/v002 编译结果除元数据外只有上述 flags 一处功能差异

官方 `cubie-a7a-radxa-display-10fhd.dtso` 用板端同一 `dtc` 编译时也会产生
相同类别的 overlay 父节点地址单元/graph 警告，因此该警告不是 v002 引入的
结构偏差。

包 `meizu-e3-dkms_0.1.10_all.deb` 的 SHA256 为
`998700ce97de18ae5fc07a754151c7d9893ef885b5abe83342af83e2191476d9`。
安装成功，DKMS 已为 `5.15.147-21-a733` 安装 `sec_ts` 和
`sgm37604a`；安装后的禁用 DTBO 与离线产物逐字节一致。

随后按 rsetup 的底层官方机制启用 v002 并运行 `u-boot-update`。验证结果：

- 全系统只有 `cubie-a7a-meizu-e3-display-v002.dtbo` 一个活动 overlay
- `l0` 只加载 v002
- `l0r` 无 overlay 且保留 `single`
- 启用后的 DTBO 哈希不变
- 启用前的配置备份为
  `/boot/extlinux/extlinux.conf.pre-meizu-v002`

第一次 `systemctl reboot` 已使 SSH 断开，但之后 48 秒 COM4 没有出现新的
BootROM、U-Boot 或内核字节。这与先前在 stock rescue 状态已经独立复现的软件
reset 失败一致，尚不能算作 v002 的实际启动结果。需要物理断电再上电后，使用
默认 `l0` 完成串口监控下的 LightDM 和 Plasma 登录测试。

本轮全部产物和日志位于：
`test_files/codexline/01_nonburst_dsi_experiment/`。

### v002 物理冷启动结果与回滚

v002 的实际黑屏启动 boot ID 为
`4c68a65b0087408385661fba98c7c793`。HDMI 与 DSI 均无输出。该次启动的
persistent kernel journal 共 1287 行，其中显示相关过滤结果 166 行；旧的
致命链路计数全部为 0：

- `sunxi_de_atomic_flush timeout`
- L1/L2 page-table invalid
- `Bug in DE`
- RCU stall
- NULL pointer / kernel panic

因此 v002 没有复现 v001 的 DE/IOMMU/RCU 崩溃，但仍不可用。

v002 的 DSI 初始化时间线：

| 内核时间 | 事件 |
|---:|---|
| 1.791252 s | 检测到 DSI-1，配置为 1080×2160@59 Hz |
| 1.842307 s | CRTC atomic enable 开始 |
| 1.843107 s | `sunxi_dsi_combophy_configure start` |
| 之后 | 不再出现 lowlevel timing、encoder enable finish 或 DSI configuration complete |

与之对照，v001 在 `sunxi_dsi_combophy_configure start` 后立即打印 lowlevel
时序，并在 2.591–2.600 秒完成 encoder enable 和
`DSI-1: Configuration complete`。这构成直接 A/B 证据：去掉 burst 后，
vendor non-burst 分支在首次 DRM atomic enable 中卡在 combo-PHY 配置内部或
紧邻其后的路径。HDMI 与 DSI 共享同一个 DRM 设备/atomic commit，因此 DSI
初始化未返回也能解释 HDMI 同时没有可用画面。

同次启动还记录到：

- SGM37604A 寄存器 `0x11` 不锁存，背光 probe 返回 `-5`
- SEC touch I²C 写失败，probe 返回 `-5`
- HDMI 在 23.798 秒连续出现 PHY I2M 读取错误

这些是显示初始化未完成时的伴随/下游故障，不能解释成旧 DE/IOMMU 崩溃再次
发生。

随后手动进入 `l0r`，由 `/proc/cmdline` 的 `single` 确认未应用 overlay。
通过串口登录执行官方回滚：

1. v002 从 `.dtbo` 改回 `.dtbo.disabled`
2. 运行 `/usr/sbin/u-boot-update`
3. 运行 `sync`

回滚后活动 DTBO 数为 0；v001/v002 均为 `.disabled`；v002 SHA256 仍为
`b05d2220b31452a46ffb83940f349d1827be0d4c8e352f36b9e04fb9b0db3be2`；
生成的 `l0` 和 `l0r` 均无 `fdtoverlays`，`l0r` 仍保留 `single`。

结论：v002 判定失败，已安全回滚。后续物理断电、U-Boot 入口和救援登录由
用户手动进入并通知完成，不再自动发送菜单按键，除非用户当次明确要求。

## 2026-07-31：RK3576 社区 Meizu E3 适配交叉分析

已对比 `radxa-meizu-e3` 社区资料、Radxa 官方 ROCK 4D/A7A overlays、
Rockchip RK3576 基础 DTS、Allwinner panel/DSI 驱动和 v001/v002 实测日志。
完整证据、哈希、差异表与后续约束记录在：

`test_files/codexline/02_rk_reference_pushpull_validation/docs/rk_reference_analysis.md`

新增的关键结论：

- 社区成功方案的精确 Meizu flags 是 burst + LPM + NO_EOT +
  CLOCK_NON_CONTINUOUS；时序中的 `vsync-len` 是 2。v001 少了
  CLOCK_NON_CONTINUOUS 且使用 vsync 4；v002 non-burst 已被实测否决。
- 社区 exit sequence 在 display-off 后等待 16 ms、sleep-in 后等待 120 ms；
  v001/v002 两处均为 0 ms。该差异不影响第一次上电，却正好影响
  LightDM -> Plasma 的输出重配，与 v001 的故障时机一致。
- 转接板 `.epro2` 网表显示 `LCD_RESET` 是连接器到屏端的直连网络，没有发现
  外部上拉。当前 A733 把它声明为 `GPIO_OPEN_DRAIN`，释放为高时电平/上升沿
  不确定，是概率性初始化的首要硬件时序嫌疑。后续应使用确定的推挽输出，但
  不直接照抄 Rockchip 驱动的 active-low 语义。
- 社区面板直接绑定 SGM37604 backlight；当前 A733 面板绑定 PWM，SGM 是另一个
  未绑定的 backlight。两套生命周期能解释概率性不亮、低亮度和调光对象错误。
- 社区 RK 与官方 A7A 都使用 SoC 硬件 I²C/TWI；当前软件 `i2c-gpio` 偏离了
  pinctrl、supply、no-suspend 和硬件控制器基线。SGM/SEC `-EIO` 应优先从
  官方 `twi2` 拓扑修正，而不是继续给驱动增加重试。
- RK3576 把 HDMI 固定到 VP0、DSI 固定到 VP1。A733 实测也分别使用 DE1 和
  DE0，但仍共享同一 sunxi DRM/DE/IOMMU 驱动；atomic timeout 后继续访问已
  解除映射的 framebuffer，才把显示故障放大成 IOMMU IRQ storm 和 RCU 锁死。

本轮没有连接或修改开发板。

## 2026-07-31：Meizu / Radxa 8HD 在 RK3576 与 A733 上的四象限结论

已把以下四种组合逐项对齐：

1. Meizu E3 + RK3576 社区成功方案；
2. Meizu E3 + A733 v001/v002；
3. Radxa Display 8HD + RK3576 官方方案；
4. Radxa Display 8HD + A733 官方方案。

完整参数表、因果链、置信度排序和分阶段测试方案记录在：

`test_files/codexline/02_rk_reference_pushpull_validation/docs/platform_comparison_analysis.md`

关键新增判断：

- 同一块官方 8HD 在 RK 上是 70 MHz、显式 480 Mb/s、burst + no-EOT；
  在 A733 上却是 70 MHz、non-burst，水平 porch 也不同。这证明 DSI host flags
  和部分传输时序属于平台驱动合同，不能跨平台逐字复制。
- 屏的物理合同不会随平台改变。Meizu 必须保留 SGM 背光、SEC 触摸、可靠推挽
  reset、精确 16/120 ms exit 延时、1080×2160/157 MHz 和已知成功的面板命令。
- 当前 v001 是混合配置：使用 A733 graph 是正确的，但又复制了 8HD PWM 背光、
  exit 零延时和 vsync=4，创建了非官方 `i2c-gpio`，并额外把无上拉的 LCD_RESET
  配成 open-drain；v002 又错误地把 8HD/A733 的 non-burst 套到约 2.24 倍有效
  lane 数据率的 Meizu。
- v002 已通过严格单变量日志判定失败：DSI enable 卡在
  `sunxi_dsi_combophy_configure start`，不得再作为后续方向。
- v001 的硬锁直接链路仍是：
  `Plasma atomic modeset -> sunxi_de_atomic_flush timeout -> 已解除映射的旧
  framebuffer 仍被 DE0 扫描 -> IOMMU IRQ storm -> RCU stall`。屏幕合同偏差
  可能是触发源，全志 DE/IOMMU 错误恢复缺陷是把显示错误放大为整机硬锁的机制。
- 下一步应先用实体官方 8HD（如果有）在同内核上做平台控制实验；然后制作只验证
  硬件 `twi2`/SGM/SEC 的 `v003-io`，通过后再制作“官方 A733 平台外壳 +
  Meizu 精确屏幕合同”的 `v003-display`。测试顺序为多次冷启动、单 DSI 反复
  DPMS/modeset、最后 HDMI+DSI，不能再以单次“亮了”作为通过标准。

本轮仍未连接或修改开发板。

## 2026-07-31：v003 DSI-only 隔离实验

按“先 DSI、后 I²C”的顺序制作
`cubie-a7a-meizu-e3-display-v003-dsi-pushpull`：

- 保留 v001 已能完成 DSI enable 的 burst + LPM + NO_EOT、1080×2160 时序；
- 删除 `i2c-gpio`、SGM37604A 和 SEC 触摸节点；
- `LCD_RESET` 从 open-drain 改为确定的 push-pull；
- HDMI 节点保持 stock，不做 DSI-only 全局禁用；
- 候选先以 disabled 安装，离线合并和 readback 验证通过后才启用；
- `l0r` 保持无 overlay 和 `single`。

第一次冷启动到登录前，HDMI 有输出，Meizu 无背光；由于本轮故意没有 SGM
节点，这个现象符合隔离条件。用户登录 Plasma 后，HDMI 立即蓝色闪屏，串口
再次出现 DE0/IOMMU 风暴。

本轮直接排除了三个对象作为硬锁的必要条件：

- SGM37604A probe/调光；
- SEC touch probe/IRQ；
- 软件 `i2c-gpio`。

push-pull reset 可以改善面板上电确定性，但没有阻止登录后的 DE/IOMMU 故障。
因此面板 reset、背光和触摸问题与整机卡死必须分层处理。

完整本轮文件位于：

`test_files/codexline/02_rk_reference_pushpull_validation/`

## 2026-07-31：重刷 t4 前最终快照

用户解除 COM4 占用后，通过串口确认当前位于 `l0r` 救援 shell；随后通过
`192.168.0.103` SSH 做了完整只读采集。当前启动信息：

```text
boot ID=d6ce9f34-06dd-4d67-927a-1b927270e582
kernel=5.15.147-21-a733
cmdline 包含 single
```

当前 extlinux 仍为：

- `default l0`
- `l0` 加载 v003
- `l0r` 无 `fdtoverlays` 且带 `single`

上一故障启动的完整 persistent journal 重新统计：

```text
sunxi_de_atomic_flush timeout = 116
PageTable Invalid             = 25679
Bug is in DE                  = 25668
is not mapped                 = 25677
RCU stall 相关行              = 21
```

首次事件：

```text
112.922995 s  atomic flush timeout
119.503159 s  L2 PageTable Invalid
119.513467 s  DE0 访问 0xfae77000
119.527320 s  L1 PageTable Invalid
119.537530 s  DE0 访问 0xfa000000
140.514976 s  rcu_preempt stall
```

刷机前快照：

```text
test_files/mainline/02_reflash_handoff/log/snapshots/20260731-preflash-r6-v003-rescue/
```

压缩包 SHA-256：

```text
866c70ab6c31ab2d965c6ba2a8c66d01fefd1584e5a387026a1bbff8f8989f26
```

重刷及后续复现的完整交接入口为：

`handoff/README.md`

下一阶段以 RSDK t4 的 6.6.98-3、U-Boot 2026.04-2 和 t4 自带 A7A Display
overlay 为新基线。禁止把旧 5.15 DTBO、extlinux 或 DKMS 二进制直接恢复到
t4。

## 2026-07-31：t4 / 6.6 上重新部署最初的 v001 `reg = <1>`

新刷写系统已通过串口和 SSH 双重确认：

```text
host=radxa-cubie-a7a
ip=192.168.0.103
os=Debian 13 (Trixie)
kernel=6.6.98-3-aw2511
u-boot-radxa-a733=2026.04-2
radxa-overlays-dkms=0.2.25
```

stock 桌面启动没有加载任何 DTBO。当前启动 journal 中 atomic flush timeout、
IOMMU PageTable Invalid、DE stale-address、RCU stall、NULL dereference、panic
和 soft lockup 的计数均为 0，故可作为新内核对照基线。

按用户要求，本轮回到最早单变量候选：历史 0.1.8 与 v001 的功能差异仅为在
`dsi0_out: port@1` 中增加 `reg = <1>`；不带入 v002 non-burst、push-pull
reset 或 v003 DSI-only 等后续修改。历史源文件 SHA256：

```text
762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e
```

从 t4 实机保存了官方 0.2.25 A7A 8HD/10FHD overlay。官方 8HD 仍使用相同
DSI0 -> virtual panel -> real panel 拓扑，但 `dsi0/ports/port@1` 仍缺少
`reg`。历史 v001 已用匹配的 6.6 headers 重新编译，未复用旧 5.15 DTBO：

```text
cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo
SHA256=31fc84eabcecaaf075215e06f67edf75dcf04d2bb67cb4f94f3a693036a74832
```

该 DTBO 已与 t4 stock DTB 通过 `fdtoverlay` 离线合并。读回确认 DSI0、
combo PHY、TCON0、虚拟/真实 panel 均为 `okay`，`port@1/reg=1`，两段 graph
双向闭合，原 v001 `dsi,flags=0xa03`、4 lanes、157 MHz、1080×2160 均未变化；
HDMI0 仍为 `okay`。

旧 0.1.9 SEC 驱动仅在 `/tmp` 做兼容性试编译，没有安装。它因
`devm_gpiod_get_from_of_node()` 消失和 6.6 I²C probe 签名变化而失败。遵循
“不与内核驱动硬刚”和“先 DSI、后 I²C”，本轮先观察显示链路；不把驱动兼容
补丁混入这个 DT 单变量测试。启动电源/regulator 告警继续按用户要求排除。

部署通过 `u-boot-update` 完成，没有手工编辑 `extlinux.conf`：

- `l0` 加载唯一 active 的 v001 DTBO；
- `l0r` 不加载 overlay，并保留 `single`；
- 启用前配置备份为
  `/boot/extlinux/backups/extlinux.conf.pre-enable-20260731-091853`；
- 救援回滚命令为：

```sh
sudo /usr/local/sbin/rollback-versioned-overlay-from-rescue \
  /boot/dtbo/cubie-a7a-meizu-e3-display-v001-reg1-t4.dtbo
```

完整基线、官方源文件、编译日志、合并读回、启动配置和本轮串口日志位于：

`test_files/mainline/03_new_kernel_overlay_validation/`

当前状态为“已部署、尚未重启”，不能将离线验证记为实际显示通过。

### t4 第一次 v001 启动结果

普通 `l0` 已实际加载 v001，boot ID 为
`7a8fe62e-d15a-4392-ad59-a74c783e215a`。DSI/PHY/TCON/panel/DRM 均完成
probe 和 bind；DSI encoder 在 8.190771 秒完成 enable，HDMI 在 13.456113 秒
完成 enable 并报告 PHY lock，SDDM 随后为两块屏分别创建 view。

本次最初观察到的“HDMI 与 DSI 均无输出”不是内核卡死。SDDM X11 的 screen
saver 和 DPMS timeout 均为 600 秒，618.132 秒两个 CRTC 被一起正常 disable；
当时 debug state 为 DE-0/DE-1 `active=0`、connector `off`、背光
`bl_power=4`。执行一次不落盘的 `xset dpms force on` 后，两个 CRTC 恢复
`active=1`，DSI encoder 再次完整 enable，HDMI PHY 再次 lock；用户现场确认
HDMI 恢复显示。

截至唤醒后，本次启动以下计数均为 0：atomic flush timeout、IOMMU
PageTable Invalid、DE stale-address、RCU stall、NULL dereference、panic、soft
lockup。DPMS 关闭前出现两次 `displl clk unable to lock`，但没有进入旧 5.15
的故障链。

DSI 物理显示仍需与背光分层判断。DT 已实例化 `0-0036` SGM37604A 和
`0-0048` SEC，但 stock 6.6 没有相应驱动，两个设备均 unbound；PD21（SGM
HWEN）也没有 consumer。当前 PWM backlight0 的 PD23/PWM4 已启用，只代表
沿用的 Radxa PWM 背光对象为 on，不能证明魅族 SGM 背光已开启。不得把当前
手机屏不亮直接归因于 DSI modeset 失败。

## 2026-07-31：t4 上安装早期 SEC/SGM 驱动后的分层结果

按照“不改当前 v001 overlay、不做后续硬件 TWI/I²C 适配”的要求，将早期
`meizu-e3-dkms 0.1.10` 的 SEC 与 SGM 行为仅做 Linux 6.6 API 移植，注册为
`meizu-e3-drivers-t4/0.1.10` DKMS。归档不包含任何 overlay；安装前后活动
DTBO 与 extlinux 哈希未变。

SGM37604A 已成功绑定 `0-0036`，创建独立的 `sgm37604a` backlight class，默认
亮度为 2000/4095，当前保持加载并配置为开机自动加载。

SEC 能读取 `AC 6F 70`、创建 Samsung input、完成固件信息读取并正确映射到
DSI-1；3000×2160 双屏布局下实际矩阵是
`0.36,0,0 / 0,1,0 / 0,0,1`。但软件复位后的 boot-complete 等待超时并连续读取
全零事件，IRQ 启用后 PD18 持续为 low，IRQ 107 稳定约 943～945 次/秒，
`irq/107-sec_ts` 占用 88%～90% CPU 并触发 `sched: RT throttling activated`。

这是一条新发现且可独立复现的 CPU 饥饿机制。它可能放大旧系统的卡顿/RCU
表现，但不是全部显示硬锁的唯一原因，因为移除 SEC/SGM/I²C 的 v003 仍复现过
DE/IOMMU 故障链。当前已动态卸载 SEC、保留 DKMS 与映射，并通过
`/etc/modprobe.d/meizu-e3-sec-ts-quarantine.conf` 阻止重启自动加载；SGM 背光
不受影响。下一步只应针对 SEC 的复位应答、事件栈清理、sense-on 与 IRQ 使能
顺序做可回退单变量验证，不应据此猜换 I²C 引脚或直接切换硬件 TWI。

完整证据和安全状态快照位于：
`test_files/mainline/03_new_kernel_overlay_validation/src/driver-port-6.6/` 与
`test_files/mainline/03_new_kernel_overlay_validation/log/post-driver-install-snapshot/`。

## 2026-07-31：t4 双屏清晰多重拖影的分层诊断

用户确认清晰、离散的旧窗口副本同时出现在 HDMI 与 DSI 两块实体屏。当前 X11
并不是两个独立 framebuffer：DSI-1 1080×2160+0+0 与 HDMI-1
1920×1080+1080+0 共同组成 3000×2160 虚拟桌面，DE-0 与 DE-1 都扫描 X
分配的同一个 framebuffer 166，只是读取不同 source rectangle。因此同步拖影在
共同的 X11/framebuffer/DE 输入侧已经形成，不能由魅族 panel、DSI PHY 或 SGM
背光单独解释。当前 SEC 已卸载并隔离，也排除了本次约 945 IRQ/s 风暴。

直接故障证据位于图形用户态栈：`glxinfo -B` 报
`couldn't find RGB GLX visual or fbconfig`；KWin X11 报
`Cannot find EGLConfig`、`Compositing disabled: no OpenGL support`，运行态明确为
`Compositing is not active`。Xorg 使用 stock modesetting + glamor + DRI2，虽先在
PowerVR BXM-4-64 上启用 glamor，随后又出现 read format/type 不匹配和
`Falling back to software`。系统同时存在 PVR `/usr/local/lib` EGL/GLES 与
Debian Mesa/GLVND EGL/GLX，是下一步应核对的接口/打包边界。

关键 stock 对照已经找到：刷机后、部署 DTBO 前的 HDMI-only boot
`0f2667c9-8449-4e65-81f5-a38debfb5801` 仅使用 1920×1080 framebuffer 163，
但其 Plasma journal 已经有完全相同的 EGLConfig 和 KWin no-OpenGL/no-compositing
错误。故基础图形栈缺陷早于本次 v001 overlay 和 SGM 驱动；DSI 更可能通过把
framebuffer 扩展为 3000×2160、启用双 CRTC shared scanout 来放大/触发原有的
非合成重绘或 cache-coherency 问题。由于用户未在 stock 单 HDMI 时做肉眼拖动
测试，不能宣称 stock 一定已有同样可见拖影，仍需 `l0r` 单 HDMI A/B 才能确认
“双输出是否为必要触发条件”。

本次运行未发现 atomic flush timeout、DE/IOMMU fault、RCU stall、NULL/panic、
underflow、FIFO 或 vblank/page-flip timeout。13:33 的双输出熄灭是 DPMS Off；
13:42 临时 `xset dpms force on` 后两路重新 enable，HDMI PHY lock。它与拖影诊断
分开记录。完整只读证据、XWD/BMP 抓屏和后续 A/B 顺序位于：

`test_files/mainline/04_new_kernel_graphics_diagnosis/`

## 2026-07-31：r6/5.15 与 t4/6.6 的 DRM/GPU 根因复核

已完成旧硬锁死、当前 GPU/EGL 异常和 v1.4.6→v1.4.8 BSP 源码的分层复核。
旧故障的直接链仍指向 sunxi DRM/DE RCQ 与 framebuffer/IOMMU 生命周期失配；
当前 PVR 内核驱动版本与旧系统相同，当前拖影则来自 Debian 13/KWin 6/Mesa 25
用户态组合的 EGL/GLX/合成问题。公开源码中最窄修复边界是
`e1524a9d77fe5a2801ead100affea1686867d377`（v1.4.8 release），最强候选是
停用每次 RCQ flush 中的 `de_top_update_force_by_ahb()`，其次是
`de_top_set_rcq_update()` 同步逻辑重写。该版本仍未完整传播 flush timeout，
因此当前结果应表述为“主要触发点被消除/显著缓解”，不能表述为已证明彻底修复。

完整证据、版本矩阵和 GPU→DRM→DE→DSI/HDMI 数据流说明见：
`test_files/mainline/04_new_kernel_graphics_diagnosis/docs/old_and_new_kernel_root_cause_analysis.md`

### 对“DSI-only 也异常”的限定

双 CRTC/共享 DE TOP 竞争应视为旧 RCQ 缺陷的放大器，而不是必要条件。单 DSI
同样经过 DE-0 RCQ，理论上可由 DSI/TCON0/vblank 时序先触发 timeout，再进入相同
stale-FB 链。另一方面，历史 `dsi-only-debug` overlay 只禁用了 `hdmi0`，没有完整
处理 HDMI TCON、DE graph、音频/extcon；对应串口记录存在 HDMI extcon probe 失败，
却没有 atomic-timeout/IOMMU/RCU 致命链。因此该次黑屏不能作为严格的纯单 DSI
同型硬锁死证据，必须与已有完整日志的双屏硬锁死分开表述。
