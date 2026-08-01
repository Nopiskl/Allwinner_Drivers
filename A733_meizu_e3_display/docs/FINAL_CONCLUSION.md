# Radxa Cubie A7A Meizu E3 显示适配与旧 BSP 双屏硬锁根因分析

更新日期：2026-08-02

本文综合整个适配周期的设备树、背光、触摸、单/双显示实验、串口日志、原厂 FAE 信息，以及 BSP 1.4.6/1.4.8 最终源码。后取得的原厂信息优先于早期猜测；已被后续证据否定或收窄的判断不会继续作为前提。

文中使用四种证据等级：

- **实验/日志事实：**开发板上实际复现，或能由原始串口、DRM 状态直接核对。
- **原厂事实：**FAE 明确提供的产品定位、测试范围和硬件时序信息。
- **源码事实：**当前归档的 BSP 最终源码可以直接确认。
- **机制推断：**能同时解释日志、实验矩阵和源码，但仍需单变量补丁或寄存器追踪才能确定具体子机制。

本文先列已知事实，再给结论，之后才逐级展开内核调用链。

## 一、已知事实

### 1.1 适配本身已经确认的事实

- Meizu E3 面板为 1080×2160 MIPI-DSI 屏，适配对象是 Radxa Cubie A7A / Allwinner A733。
- `v001-reg1` overlay 按 Radxa 官方 A7A Display graph 补入 `dsi0/ports/port@1 reg = <1>`。面板能完成初始化并正常显示，因此该 graph 修正是有效适配，不是运行期硬锁的原因。
- SGM37604A 背光驱动能正常控制背光；Samsung SEC 触摸及 X11 输出映射也曾验证可用。决定性硬锁交叉实验没有安装或加载触摸驱动，所以触摸不在故障变量中。
- T4 / Linux 6.6 环境使用同一最初 overlay 方向并加入背光、触摸后，DSI 能长时间运行，没有出现旧系统的 DE IOMMU fault → RCU stall 链。
- T4 上观察到的窗口拖影属于 GPU/EGL/KWin 合成路径的相邻问题：画面异常但内核仍能调度，与旧 5.15 的整机硬锁不是同一故障。

### 1.2 原厂 FAE 最终澄清

- BSP 1.4.6 使用的也是旧 DRM；不能再描述成“原厂旧系统只走 disp2”。当时主要在 Android/SurfaceFlinger/HWC 用户态验证，而不是 Debian+X11。
- 1.4.6 DRM 的产品定位是试用版本。FAE 明确指出 `TCON-LCD + TCON-TV` 配合存在问题。
- **撤回旧表述：**“原厂确认双 MIPI、LVDS 等同类 LCD-TCON 路径正常”并不准确。现有信息只支持这些组合在 Android 测试中曾正常运行，不能外推为原厂对同类 LCD-TCON 在 Debian、其他用户态或全部 DRM 事务下的通用确认。
- 1.4.8 才是原厂转入稳定验证的新 DRM 路径；本机 Meizu E3 和 Radxa 官方 DSI 屏呈现相同的版本改善边界。涉及双 DSI、DSI+LVDS/RGB/eDP 的原厂运行信息仍须限定在 Android 测试范围内。
- DE 有自己的更新和完成时序，因此部分函数按设计必须默认 complete。这个设计事实不能被简化成“所有提交都必须等待通用 CRTC vblank”。
- 新驱动完整接入 extcon；CRTC 发生变化时会刷新相关状态。extcon/刷新解决的是连接、mode/timing 与完成判断的一致性。
- Radxa 官方 DSI 屏在 1.4.6 也遇到同类问题，切换到 1.4.8 后解决；Meizu E3 呈现相同版本边界。

这些原厂事实排除了两个早期错误前提：Android 并没有绕开 DRM；原厂也不是在 1.4.6 上完成了 Debian+X11 混合 TCON 的稳定性验证。

### 1.3 受控交叉实验

本轮严格保持以下变量不变：

- 内核：`5.15.147-21-a733 #21`。
- overlay：最初版本加官方 A7A graph 所需 `dsi0/ports/port@1 reg = <1>`，即 `v001-reg1`。
- 背光：仅安装已经验证可用的 `sgm37604a` DKMS。
- 触摸：未安装、未加载，因此触摸和坐标映射不在变量中。
- `hdmi-toggle-once.service` 已禁用。
- `/etc/udev/rules.d/60-hdmi-hotplug.rules` 已屏蔽。
- 没有加入后续 non-burst、push-pull reset、硬件 TWI 等试验性 DTS 改动。

在这个完全相同的环境中得到三种结果：

| 场景 | 结果 | 能排除或证明什么 |
|---|---|---|
| HDMI 物理断开，连续 3 次单 DSI 启动并登录 Plasma | 正常；两次 DSI full modeset 也完成 | DSI overlay、面板初始化和背光本身不足以触发硬锁 |
| Plasma 已经运行，再插入 HDMI 并扩展为双屏 | 正常；3000×2160 共用 framebuffer，两路 `err=0` | 双 CRTC 稳态本身也不是充分条件 |
| HDMI 从开机时即连接，SDDM 正常，登录 Plasma | 两屏同时冻结，内核硬锁 | 故障窗口被限定在 SDDM 到用户会话的双输出 atomic/framebuffer 交接 |

这个对照也解释了为什么过去看起来“有时正常、有时卡死”：决定结果的不是串口最后显示的文本，也不是简单的“有没有 DSI”，而是显示硬件正在扫描哪块 framebuffer、登录时双 CRTC 的提交先后顺序、RCQ 在相应 vblank/忙闲窗口是否真正完成。这个窗口具有竞争性，所以旧系统早期表现为概率故障；当前流程把 HDMI 从启动前就接入，并固定在登录时重建双屏布局，因而命中率明显提高。

补充版本对照：T4/6.6 在同一 panel/overlay 方向下未进入旧故障链；因此问题不能归结为 Meizu 面板私有初始化序列。

### 1.4 直接内核日志事实

#### 1.4.1 冷启动 HDMI+DSI 登录硬锁

原始串口文件：

`test_files/mainline/06_old_kernel_dual_display_crosscheck/log/serial-COM4.log`

SHA-256：

`5509B5BE4B0CCB54DCB601B41266637F20A2ED05FEAF79D7562722582E5E8653`

时间线：

1. 约 `9.767 s`，SDDM 和 tty 登录已经启动，用户也确认登录界面视觉正常。
2. 登录 Plasma 后，`34.087194 s` 首次出现 DE0 `L2 PageTable Invalid`，地址 `0xfa1f5000`。
3. 随后出现 3536 次 L1 fault，反复指向 `0xfa000000`；合计 3537 次 DE0 invalid-address。
4. DE1 invalid-address 次数为 0。
5. `55.187693 s` 和 `118.210362 s`，CPU6 报告 RCU self-detected stall。
6. 串口至少到 `121.602172 s` 仍在输出 DE0 fault，屏幕和系统都不能交互。

从第一次 fault 到最后一条统计区间约 87.505 秒，共 3537 次，平均约 40.42 次/秒，即约每 24.75 毫秒一次。这个周期符合显示硬件不断重试读取同一无效 scanout 地址，而不是一次性的普通应用崩溃。

本次没有看到：

- `sunxi_de_atomic_flush timeout`；
- NULL pointer dereference；
- soft lockup；
- DE1 的页表错误。

这三点很重要：本次内核不是先因为 NULL 指针直接 panic，也不能把 `atomic_flush timeout` 当成每次故障的必要起点。第一个可见的内核级致命事件就是 DE0 对无效映射的访问。

#### 1.4.2 旧原始日志证明“释放后仍扫描”

更早的原始日志：

`test_files/codexline/02_rk_reference_pushpull_validation/log/serial-v003-boot.log`

该日志在 IOMMU 异常后打印了 sunxi DRM 驱动自己的 framebuffer 环形追踪。关键记录按内核纳秒时间换算如下：

| 事件 | 地址 | 时间 |
|---|---:|---:|
| 旧 framebuffer 最后一次提交 | `0xf4000000` | `218498676811 ns` |
| 驱动记录旧 framebuffer 已解除映射 | `0xf4000000`, `map:0` | `218562308519 ns` |
| 新 framebuffer 已处于 mapped/提交记录 | `0xfc000000`, `map:1` | `218614201436 ns` |
| DE0 首次访问旧 framebuffer 内部并发生 fault | `0xf5697000` | `218723012000 ns` |

时间关系：

- 首次 fault 比旧 framebuffer 的 unmap 晚约 `160.703 ms`。
- 首次 fault 比新 `0xfc000000` framebuffer 的记录晚约 `108.811 ms`。
- 旧 `0xf4000000` framebuffer 为 3000×2160、pitch 12000、XR24，理论大小为 25,920,000 字节，页对齐约 `0x18b9000`。
- `0xf5697000 - 0xf4000000 = 0x1697000`，明确落在这块旧 framebuffer 的地址范围内。

因此它不是随机野指针，也不是 GPU 纹理地址碰巧相同，而是 DE 正在扫描一块 DRM 已经解除映射的旧 scanout framebuffer。随后故障回到其基地址 `0xf4000000` 并持续重复。

这份旧日志同样没有打印 `sunxi_de_atomic_flush timeout`。因此应修正此前预测：

- timeout 在部分旧故障中出现过，说明 RCQ 更新确实可能长时间不能完成；
- 但无 timeout 时仍能发生旧 FB 被释放后继续扫描；
- 真正根因是“硬件完成状态和 FB 生命周期不一致”，timeout 只是其中一种可见症状。

### 1.5 已知事实的边界

- 日志能 100% 证明 DE0 在访问无效、且历史追踪中已经解除映射的 scanout 地址。
- 源码能直接证明旧驱动存在 RCQ 失败无法上传、page-flip 仍完成、跳过标准 vblank wait 并立即 cleanup old plane 的生命周期缺口。
- “共享 force-by-AHB 覆盖 disp0 RCQ update 是哪一次故障的唯一漏切原因”仍属于高置信度机制推断；需要 B1/B2/B3 单变量内核实验或实际 OVL/RCQ 寄存器 readback 才能最终拆分贡献。

## 二、最终结论

这次实验已经把问题从“DSI 面板、设备树或 GPU 可能有问题”收窄到了一个很具体的内核故障：

> 本机 `5.15.147-21-a733 #21` 所用的 sunxi DRM/DE 在 HDMI+DSI 登录切换期间，没有可靠地保证新的 RCQ/scanout 地址已经被显示硬件接受，就允许 DRM 释放旧 framebuffer。旧 framebuffer 的 IOMMU 映射随后被删除，但 DE0 仍继续扫描旧地址，于是产生连续的 `PageTable Invalid` 中断。中断风暴占用 CPU，RCU 无法调度，最后表现为 HDMI、DSI 和整个系统同时冻结。

这里的“旧地址仍被扫描”不是推测：旧故障日志中的驱动自带 framebuffer 跟踪记录显示，`0xf4000000` 对应的旧 framebuffer 已经被标为 `map:0` 并记录了 `unmap_ts`，之后 DE0 又访问了这个 framebuffer 范围内的 `0xf5697000`，继而反复访问基地址 `0xf4000000`。本次冷启动登录故障则以相同形式反复访问另一块旧地址 `0xfa000000`。

目前可作如下定性：

| 判断 | 置信度 | 说明 |
|---|---:|---|
| DE0 正在读取已经解除 IOMMU 映射的旧 scanout framebuffer | 100% | 驱动 map/unmap 追踪、故障地址范围和 IOMMU 日志直接互证 |
| 本机 #21 故障属于 sunxi DRM/DE 的 atomic、RCQ 完成判定与 framebuffer 生命周期同步 | 95% | 源码中存在明确的完成错误不上传、跳过 vblank 等待、立即清理旧 FB 的组合缺口；该判断不外推为所有 v1.4.6 产品均会失败 |
| 1.4.6 试用版 DRM 的 `TCON-LCD + TCON-TV` 混合提交是首要拓扑触发条件 | 很高 | FAE 明确指出 LCD-TCON 与 TV-TCON 配合有问题；A733 DTS 和 TCON 驱动证明 DSI/LVDS/RGB 与 HDMI 分属两套时序、IRQ 和扫描线判定路径；本机单 DSI、单 HDMI、冷启动双屏和桌面后热插实验矩阵与此一致。Android 下双 MIPI/LVDS 的运行现象仅作范围受限的旁证，不作为通用正常性证明 |
| HDMI 开机存在、SDDM 切换到 Plasma 的双 CRTC 重配置是主要放大窗口 | 90% | 同一内核、DTBO 和背光下，单 DSI 与桌面后热插 HDMI 均通过，只有冷启动双屏登录稳定复现 |
| v1.4.8 阻止了 DE352 上不受支持的 DFS/共享 RCQ-control 强写 | 源码差异确定；故障因果高 | DE352 两版都未声明 `support_dfs`；1.4.6 却无条件 dirty DFS shadow，并在每个 CRTC flush 时把无 display 偏移的整块 RCQ control 强写到 disp0；1.4.8 先按能力返回且取消 force-by-AHB。Radxa 官方屏与本机屏均表现为 1.4.6 复现、1.4.8 消失，显著提高版本级因果置信度；具体由哪一项子改动解决仍需单变量 A/B |
| v1.4.8 删除 `current_line > 0` 的 RCQ control 整寄存器直写 | 中高 | A733/DE352 直接调用该函数；新版只在 DE busy 条件成立后做 read-modify-write，避免绕过条件并覆盖同寄存器其他位 |
| 静态 RTMX line-buffer 写法能解释两版稳定性差异 | 低 | 当前归档的 BSP 1.4.6 与 BSP 1.4.8 源码都采用 disp0=`0x2000`、disp1=`0x1000`；这是共有实现，不是判别变量 |
| PVR GPU 内核驱动是硬锁的主要根因 | 低于 10% | 故障 master 是 DE0，不是 GPU；新旧系统 PVR 版本一致；GPU 主要负责提高提交频率、暴露内核错误 |
| `reg = <1>`、面板初始化、背光或触摸导致本次硬锁 | 接近 0% | SDDM 和单 DSI 已正常显示；故障发生在图形会话切换后的 DE 内存访问阶段 |

因此，当前不能再把问题归因于“DSI 一启用就必然异常”，也不能简单称为 GPU 绘制错误。更精确的说法是：

> DSI 经 `TCON-LCD`、HDMI 经 `TCON-TV`。1.4.6 试用版 DRM 在二者参与同一次登录重配置时，未可靠协调两套独立的时序/完成域，显著扩大了 DE/RCQ 同步漏洞；真正令内核失效的是显示控制器读取已解除映射的 framebuffer。

### 2.1 根因必须分成四层

| 层级 | 本次定位 | 证据性质 |
|---|---|---|
| 直接致死原因 | DE0 继续扫描已经 IOMMU unmap 的旧 framebuffer | 日志直接证明 |
| 内核安全缺口 | DE/RCQ 完成语义与 DRM framebuffer 生命周期不同步；失败不能上传，old FB 又被立即 cleanup | 源码直接证明 |
| 首要拓扑触发器 | 1.4.6 试用 DRM 的 `TCON-LCD + TCON-TV` 混合重配置 | 原厂信息、DTS/驱动拓扑和实验矩阵共同证明 |
| 最可能底层机制 | DE352 不支持 DFS 却 dirty 共享 RCQ-control shadow；每路 flush 的 force-by-AHB 固定写 disp0，再叠加旧 RCQ update 条件 | 两版源码差异与全部现象吻合；具体子项仍需单变量 A/B |

### 2.2 完整故障链

```text
Meizu E3 overlay、面板与背光正常初始化
        ↓
HDMI 从开机即存在，SDDM 初始双屏状态建立成功
        ↓
登录 Plasma 时重建 3000×2160 root framebuffer 和双 CRTC 状态
        ↓
TCON-LCD 与 TCON-TV 在各自时序域中被逐个 atomic_flush
        ↓
1.4.6 DE352 的共享 RCQ/DFS/force 路径制造地址漏切或完成状态失配
        ↓
DE 自有完成路径仍被视作 complete，page flip/commit 被宣布完成
        ↓
厂商 commit tail 跳过标准 vblank wait，cleanup old planes
        ↓
旧 framebuffer destroy，IOMMU 映射被删除
        ↓
DE0 仍扫描旧 IOVA
        ↓
PageTable Invalid 中断约 40.42 次/秒持续发生
        ↓
RCU grace-period 线程饥饿，HDMI、DSI、SSH、心跳一起冻结
```

### 2.3 版本结论

- 工程上可以判断 BSP 1.4.8 已解决或避开本次实际触发链；依据是 Radxa 官方屏与本机 panel 的同一版本边界、本机 T4 实测以及可见的 DE/RCQ/CRTC 状态改动。Android 产品测试信息仅作为辅助证据。
- 不能把改善简单归因于 Linux 通用内核从 5.15 升到 6.6；关键判别变量位于 Allwinner BSP 显示驱动。
- 也不能声称 1.4.8 已形式化消灭所有 stale-FB 风险：其 `sunxi_de_atomic_flush()` 仍为 `void`，厂商 tail 仍没有恢复通用 vblank wait。新版更像把主触发路径修到稳定，而非建立了完整的失败传播和 old-FB 保活防线。

## 三、A733 显示拓扑与双 CRTC 事务

### 3.1 TCON-LCD 与 TCON-TV 不是名称差异

A733 设备树和驱动把输出明确分成两类：

| 输出 | A733 TCON 类型 | 设备树路径 |
|---|---|---|
| DSI0/DSI1、LVDS0/1、RGB0/1 | `TCON-LCD` | `tcon0/1/2`，`compatible = "allwinner,tcon-lcd"` |
| HDMI0 | `TCON-TV` | `tcon3`，`compatible = "allwinner,tcon-tv"` |
| eDP0 | `TCON-TV` | `tcon4`，`compatible = "allwinner,tcon-tv"` |

源码位置为 `configs/linux-5.15/sun60iw2p1.dtsi:3838-4218`。其中 `tcon0` 的输出端点直接
列出 DSI0、DSI1、LVDS0 和 RGB0；`tcon3` 只连接 HDMI0，`tcon4` 连接 eDP0。这里也修正
一个容易混淆的表述：eDP 在 A733 上属于 `TCON-TV`。Android 中观察到的 DSI+eDP
运行结果只能作为特定产品路径的辅助证据，不能外推为 Debian 下混合 TCON 已被普遍验证，
更不能反推 1.4.6 的 LCD+TV 本来就稳定。

`sunxi_tcon.c` 并不是只给两类输出换一个名字。它根据 compatible 设置 `TCON_LCD` 或
`TCON_TV`（26～81 行），随后分别使用：

- `LCD_IRQ_TCON0_VBLK` 与 `LCD_IRQ_TCON1_VBLK` 查询不同 vblank IRQ（438～445 行）；
- `tcon_lcd_get_cur_line()` 与 `tcon_tv_get_cur_line()` 读取不同扫描线计数器；
- 各自的 `get_start_delay()` 判断可安全同步窗口（849～882 行）；
- 各自的 FIFO status 与 vblank enable 函数（947～969 行）。

所以一个 DRM atomic state 可以逻辑上同时包含两个 CRTC，但它不会把 LCD-TCON 和
TV-TCON 变成同一硬件时钟、同一 vblank 或一个 group-latch。helper 仍逐个 CRTC flush，
每一路按自己的时序域锁存。1.4.6 试用版驱动若在两路之间复用/强写共享 DE/RCQ control，
或按其中一路的状态过早宣布 complete，就会形成一个 CRTC 已切换、另一个仍扫描旧地址的
不对称事务。

这一定位与全部实验严格闭合：

- HDMI-only 只有 `TCON-TV`，正常；
- DSI-only 只有 `TCON-LCD`，连续启动和 full modeset 正常；
- 双 MIPI、DSI+LVDS/RGB 主要是 `TCON-LCD + TCON-LCD`；本项目没有在 Debian 下完成这些组合的交叉实验，现有“可运行”信息只来自 Android 测试；
- HDMI+DSI 是 `TCON-TV + TCON-LCD`，旧版在冷启动登录交接稳定触发；
- 桌面稳定后再热插 HDMI 能运行，说明混合 TCON 的稳态输出并非硬件上不可实现，缺陷在
  混合域的重配置/完成事务，而不是两种接口电气上不能并存。

因此因果层级应调整为：**混合 TCON 是首要拓扑触发器，旧 DE352 RCQ/DFS/force 行为是
制造错误锁存的底层机制，X11 立即销毁旧 FB 是把错误升级为 IOMMU 风暴的生命周期条件，
HDMI HPD/登录 modeset 是提高命中率的放大器。**


### 3.2 为什么 3000×2160 大桌面仍不是硬件 group-latch

本机 3000×2160 root framebuffer 只统一了 X11 坐标空间。Linux 5.15 与 6.6 的
`drm_atomic_helper_commit_planes()` 在关键顺序上都是先更新 plane，再逐个 CRTC 调用
`atomic_flush()`。两个 CRTC 各有 mode、vblank 相位和 RCQ update，没有 group-latch。

SDDM 两屏正常表示初始 enable 最终成功；当时没有一个即将被销毁的旧桌面 FB。登录 Plasma
后的 root-FB/布局交接才同时具备“旧 FB 正在扫描、两个 CRTC 连续 flush、HDMI 可能改变
connector/mode、旧 FB 最后引用释放”。静态登录画面正常并不能证明下一次交接安全。

逻辑上的一次 DRM atomic state 只保证软件状态整体校验和提交顺序；它不自动赋予两个不同 TCON 一个共同的物理锁存边沿。这个区别正是“登录界面两屏都正常”与“登录后下一次交接硬锁”能够同时成立的原因。

## 四、逐级内核调用链与源码

以下旧版代码来自 `bsp/radxa-allwinner-bsp/`（BSP 1.4.6）；标准 DRM helper 来自 `bsp/radxa-kernel-a733/`。行号以当前归档文件为准。

先给出函数级主链，后面的每一节按此顺序展开：

```text
sunxi_drm_atomic_helper_commit_tail()
  -> drm_atomic_helper_commit_modeset_disables/enables()
  -> drm_atomic_helper_commit_planes()
       -> sunxi_plane_atomic_update()
            -> sunxi_de_channel_update()
                 -> de_ovl.c 写入 framebuffer DMA shadow
       -> sunxi_crtc_atomic_flush()             [逐个 CRTC]
            -> sunxi_de_atomic_flush()
                 -> de_top_freq_div_apply()
                 -> de_top_update_force_by_ahb() [1.4.6]
                 -> de_top_set_rcq_update()
                 -> check_update_finished()
            -> sunxi_crtc_finish_page_flip()
  -> drm_atomic_helper_fake_vblank()/commit_hw_done()
  -> 跳过 drm_atomic_helper_wait_for_vblanks()
  -> drm_atomic_helper_cleanup_planes()
       -> sunxi_drm_gem_fb_destroy()
            -> GEM/dma-buf/CMA 释放与 IOMMU unmap
  -> DE 若仍读取旧 IOVA，则进入 sunxi_iommu_irq()
```

### 4.1 FAE 所说的 DE 自有 complete 应如何理解

FAE 的说明解释了 sunxi DRM 为什么没有完全照搬通用 DRM 的 vblank 完成模型。驱动调用链
确实是：

```text
sunxi_de_atomic_flush() 由 DE/RCQ 自己判断更新完成
        ↓
sunxi_crtc_finish_page_flip()
        ↓
drm_atomic_helper_fake_vblank() / commit_hw_done()
        ↓
跳过通用 wait_for_vblanks()
        ↓
cleanup old planes
```

因此“默认 complete”本身是厂商硬件模型的设计选择，不应简单改成“所有提交强等标准
CRTC vblank”。但该设计有一个不可妥协的前提：**DE 自己报告 complete 时，新 RCQ 地址
必须已经被硬件可靠接受，或者旧 framebuffer 必须继续保活。**

1.4.6 的实际问题不是“使用了 DE 自有时序”这件事，而是 DE 请求、状态刷新和 complete
之间存在失配，且上层没有安全兜底。`sunxi_de_atomic_flush()` 返回 `void`；RCQ timeout
只打印日志；`sunxi_crtc_finish_page_flip()` 仍会完成 event；custom commit tail 随即清理
old plane。即使某些函数按硬件设计必须默认 complete，也不能允许 complete 早于真实
scanout 地址交接。
### 4.2 framebuffer 地址进入硬件 shadow register

`drivers/drm/sunxi_device/hardware/lowlevel_de/ovl/de_ovl.c:245-275`：

```c
format_info = drm_format_info(fb->format->format);
#if LINUX_VERSION_CODE <= KERNEL_VERSION(6, 1, 0)
for (i = 0; i < format_info->num_planes; i++) {
        gem = drm_fb_cma_get_gem_obj(fb, i);
        if (gem) {
                addr_tmp = (u64)(gem->paddr) + fb->offsets[i];
                addr[i] = addr_tmp
                        + pitch[i] * y[i] + (x[i] * bpp[i] >> 3);
        }
}
#endif

reg->lay[layer_id].top_laddr0.dwval = (u32)addr[0];
reg->lay[layer_id].top_laddr1.dwval = (u32)addr[1];
reg->lay[layer_id].top_laddr2.dwval = (u32)addr[2];
```

`sunxi_drm_debug.c:248-266` 同时把这次提交使用的 FB 和 DMA 地址写入
环形追踪：

```c
frame->data[index].update_ts = ktime_get();
frame->data[index].fb = fb;
frame->data[index].mapped = 1;
...
frame->data[index].dma_addr = get_gem_device_addr(fb->obj[0]);
frame->data[index].name = fb->obj[0]->name;
```

这解释了旧原始日志第 6065～6068 行为何能精确列出：

```text
0xf4000000 map:0 unmap-ts:218562308519
0xfc000000 map:1 unmap-ts:0
```

日志中的地址与驱动实际提交给 DE 的 scanout DMA 地址来自同一对象。

### 4.3 旧 RCQ flush：失败只打印，不能向上传递

`sunxi_de.c:716-769`：

```c
if (use_rcq) {
        check_update_finished(hwde);

        if (engine->de_devfreq_auto)
                sunxi_de_auto_calc_freq_and_apply(engine->display_out);

        de_top_update_force_by_ahb(engine->top_hdl);

        if (engine->match_data->rcq_wait_line)
                rcq_update_timer_start(hwde);
        else
                de_top_set_rcq_update(engine->top_hdl, hwde->id, 1);

        sunxi_drm_crtc_prepare_vblank_event(hwde->scrtc);
        hwde->last_rcq_vsync = hwde->vsync_count;
}

if (in_task() && use_rcq)
        timeout = read_poll_timeout(check_update_finished, is_finished,
                                    is_finished, 2000, 50000, false, hwde);

if (timeout)
        DRM_INFO("%s timeout\n", __func__);
```

A733 的 match data 为 `de352_data`，`rcq_wait_line` 保持默认 `false`，所以本机执行的是
上面 `else` 中的直接 `de_top_set_rcq_update()`；hrtimer 分支不属于本机调用链。

函数声明为：

```c
void sunxi_de_atomic_flush(...)
```

所以无论 `timeout` 是真是假，调用者得到的都是一次普通的 `void` 返回。
本次冷启动没有打印 timeout，说明还存在完成位假阳性、旧地址未真正锁存或双路
状态交错等路径；但一旦发生显式 timeout，这个接口同样没有办法阻止上层清理旧 FB。

### 4.4 旧 `de_top_set_rcq_update()` 也不能报告“根本没有发出 update”

`de_top.c:1080-1103`：

```c
do {
        local_irq_save(flag);
        busy = !!(readl(reg_base2) & 0x10);
        if (busy) {
                reg_val = readl(reg_base);
                reg_val = SET_BITS(0, 1, reg_val, update ? 0x1 : 0x0);
                writel(reg_val, reg_base);
                local_irq_restore(flag);
                break;
        }

        cur_line = (readl(reg_base3) & 0xffff0000) >> 16;
        if (cur_line > 0) {
                writel(update ? 1 : 0, reg_base);
                local_irq_restore(flag);
                break;
        }
        local_irq_restore(flag);
        usleep_range(5, 10);
        i++;
} while (i < 10000);

return 0;
```

即使循环达到 10000 次仍没有进入任何写寄存器分支，函数也返回 0。旧版本还在
`current_line > 0` 时绕过 read-modify-write，直接 `writel(1, reg_base)`。因此这里
既缺少可靠错误码，也有扫描时刻相关的特殊写法。

### 4.5 CRTC 把 RCQ 返回等同于 page flip 完成

`sunxi_drm_crtc.c:2030-2040`：

```c
sunxi_de_atomic_flush(scrtc->sunxi_de, backend_data, &cfg);
if (scrtc_state->atomic_flush)
        scrtc_state->atomic_flush(scrtc_state->output_dev_data);

/*
 * ... perform the page_flip after the rcq_finished
 * to ensure that the fence of the current frame is signaled !
 */
sunxi_crtc_finish_page_flip(crtc->dev, scrtc);
```

注释假设已经 `rcq_finished`，但调用接口没有提供这一保证。此处会发送 vblank event
并清除 event，从 DRM/fence 角度把这一帧视为完成。

### 4.6 厂商 atomic commit tail 随后立即回收 old plane

`sunxi_drm_drv.c:181-200` 原文：

```c
static void sunxi_drm_atomic_helper_commit_tail(
                struct drm_atomic_state *old_state)
{
        struct drm_device *dev = old_state->dev;

        drm_atomic_helper_commit_modeset_disables(dev, old_state);
        drm_atomic_helper_commit_modeset_enables(dev, old_state);
        drm_atomic_helper_commit_planes(dev, old_state, 0);
        drm_atomic_helper_fake_vblank(old_state);
        drm_atomic_helper_commit_hw_done(old_state);

/*      drm_atomic_helper_wait_for_vblanks(dev, old_state);*/

        drm_atomic_helper_cleanup_planes(dev, old_state);
}
```

这里完整展示了生命周期断点：标准 DRM helper 中保护 old framebuffer 的 vblank
等待被注释，`cleanup_planes()` 紧接着运行。只要硬件并未真正切换地址，old FB 的
软件引用与硬件使用状态就发生分裂。

作为对照，工作区 `bsp/radxa-kernel-a733` 的 Linux 5.15 Git object 中，标准
`drivers/gpu/drm/drm_atomic_helper.c:1604-1620` 明确采用相反顺序：

```c
void drm_atomic_helper_commit_tail(struct drm_atomic_state *old_state)
{
        struct drm_device *dev = old_state->dev;

        drm_atomic_helper_commit_modeset_disables(dev, old_state);
        drm_atomic_helper_commit_planes(dev, old_state, 0);
        drm_atomic_helper_commit_modeset_enables(dev, old_state);
        drm_atomic_helper_fake_vblank(old_state);
        drm_atomic_helper_commit_hw_done(old_state);
        drm_atomic_helper_wait_for_vblanks(dev, old_state);
        drm_atomic_helper_cleanup_planes(dev, old_state);
}
```

同文件对 `drm_atomic_helper_wait_for_flip_done()` 的说明还直接写明：应在调用
`drm_atomic_helper_cleanup_planes()` 清理旧 framebuffer **之前**等待受影响 CRTC
完成 page flip。厂商路径跳过等待并不是 Linux DRM 的默认生命周期安排。

此外两段代码还有第二个顺序差异：Linux 默认是 `disables → planes → enables`，
厂商路径是 `disables → enables → planes`。在完整 modeset 中，这允许输出/RTMX 在
新 plane 地址写入前先被 enable，扩大硬件短暂继续使用旧 shadow/scanout 地址的
窗口。这是源码确认的额外风险面，但 v1.4.8 仍保留该顺序，所以它更像放大器，
不能单独解释为什么新版当前没有复现。

### 4.7 framebuffer destroy 与日志 `map:0` 是同一条释放路径

`sunxi_drm_drv.c:98-102`：

```c
static void sunxi_drm_gem_fb_destroy(struct drm_framebuffer *fb)
{
        sunxidrm_debug_trace_framebuffer_unmap(fb);
        drm_gem_fb_destroy(fb);
}
```

`sunxi_drm_debug.c:292-297`：

```c
if (frame->data[i].fb == fb &&
    frame->data[i].name == fb->obj[0]->name &&
    frame->data[i].dma_addr == dma_addr) {
        frame->data[i].mapped = 0;
        frame->data[i].unmap_ts = ktime_get();
}
```

`sunxi_drm_gem.c:75-97` 随后解除 imported dma-buf，或者对本地 CMA buffer 调用
`dma_free_wc()`，最后释放 GEM object。IOMMU unmap 路径再删除页表映射并失效
TLB/PTW。因此旧日志中的 `map:0` 不是推测性标签，而是 framebuffer destroy 路径
在真正释放映射前留下的内核时间戳。

### 4.8 IOMMU handler 为什么不能自愈

`drivers/iommu/sunxi-iommu-v2.c:1345-1418` 的关键部分：

```c
if (inter_status_reg & IOMMU_INT_L1PG_STA_MASK)
        pr_err("L1 PageTable Invalid\n");
else if (inter_status_reg & IOMMU_INT_L2PG_STA_MASK)
        pr_err("L2 PageTable Invalid\n");

sunxi_iova_invalid_helper(addr_reg);
pr_err("Bug is in %s module, invalid address: 0x%llx ...\n",
       plat_data->master[...], addr_reg, ...);

sunxi_tlb_invalid_locked(addr_reg, addr_reg + 4 * SPAGE_SIZE);
sunxi_ptw_cache_invalid_locked(addr_reg, addr_reg + 2 * SPD_SIZE);
sunxi_iommu_write(iommu, offset + IOMMU_INT_CLR_REG, int_clear_mask);
...
return IRQ_HANDLED;
```

handler 清除 fault 状态并返回，却没有 disable/mask/stop 仍在读取旧地址的 DE。
于是本次日志第 496 行第一次 L2 fault 后，紧接着连续出现 `0xfa000000`；第 3908、
14098 行最终报告 CPU6 RCU stall。这正是源码所允许的循环行为。

日志只点名 DE0，并不意味着 HDMI 与 DSI 是两个独立故障。DE0 是本次仍持有旧地址的 DMA master；持续 IRQ 占用 CPU、阻塞 RCU 和 atomic/display 工作后，DE1、用户态、SSH 与心跳同样无法继续推进，所以两块屏幕会一起冻结，而 DE1 不必再产生一次页表错误。

### 4.9 日志—函数—故障后果闭环

| 阶段 | 源码位置 | 原始日志证据 | 确定的含义 |
|---|---|---|---|
| 提交 scanout | `de_ovl.c`、`sunxi_drm_debug.c` | 旧日志 6065～6068 行记录 `f400 map:0`、`fc00 map:1` | 驱动已经提交新 FB，并记录旧 FB 状态 |
| old FB 被销毁 | `sunxi_drm_drv.c:98-102`、`sunxi_drm_debug.c:273-303` | `f400 unmap-ts:218562308519` | 软件生命周期已结束，映射进入释放路径 |
| DE 仍读 old FB | `sunxi_de.c`、`de_top.c`、OVL address register | 旧日志 432～438 行访问 `f5697000`，继而 `f4000000` | RCQ/硬件实际地址没有跟随软件状态完成切换 |
| 页表异常循环 | `sunxi-iommu-v2.c:1345-1418` | 本次日志 496 行起，3537 次 DE0 invalid-address | handler 清 fault 但 DE 继续重试 |
| 整机失去调度 | 同一 IRQ 循环持续占用 CPU6 | 本次日志 3908、14098 行 RCU stall | 两屏、SSH、心跳一起冻结是后果，不是多个独立故障 |

这一调用链解释了为什么串口每次停在不同一行、屏幕有时停在日志、有时停在鼠标或桌面：真正的失效发生在异步 DMA/IRQ/RCU 路径，普通启动输出只是硬锁发生前最后来得及显示或打印的内容。

## 五、BSP 1.4.6 与 1.4.8 的关键差异

本节只比较两个 BSP 最终源码树，不依赖 Radxa 仓库的提交次数来代替功能分析。

### 5.1 旧版共享 DE TOP/RCQ block 的危险条件

`sunxi_de.c` 的 `de_rtmx_init_rcq()` 会把同一个 `detop_hdl->block` 加入每个 display 的 RCQ block 列表。初始化 display 0、再初始化 display 1 时，每个底层 `reg_blk->rcq_hd` 都被重新赋值。因为 DE TOP 是单例，最后一次初始化可能覆盖共享 TOP block 的单个 `rcq_hd` 回指。

这意味着双 CRTC 同时使用共享 TOP 时，dirty 标记究竟属于哪一路 RCQ header 存在明确的设计歧义。更关键的是，这个 TOP block 的 `reg_addr` 在 `de_top_create()` 中只按
`de_reg_base + rcq_ctl_offset` 建立，没有加入 display 的 `0x40` 偏移；它实际指向 disp0
RCQ control。旧 BSP 又在**每个** CRTC flush 中调用 `de_top_update_force_by_ahb()`，所以
flush disp1 时也可能根据共享/后绑定的 dirty header，把整块 shadow 强写到 disp0 控制寄存器。

这与实验现象高度一致：单 DSI 只有一条 RCQ 控制流，顺序写后通常还能完成；双屏登录时
disp0/disp1 连续 flush，disp1 路径可能改写 disp0 的 RCQ control，导致 disp0 的新 OVL
地址没有锁存，而软件仍继续释放 old FB。它仍需寄存器追踪完成最后一步实证，但已经是
两个 BSP 源码差异中最具体的直接机制。

### 5.2 v1.4.8 对 DE352 DFS/RCQ-control 路径的精确修正

v1.4.8 的 `sunxi_de.c:731`：

```c
// de_top_update_force_by_ahb(engine->top_hdl);
```

旧版被停用的函数写的是整个 block，并未接收 display id：

```c
if (hdl->private->reg_blks[0].rcq_hd &&
    hdl->private->reg_blks[0].rcq_hd->dirty.dwval) {
        *((u32 *)hdl->private->reg_blks[0].reg_addr) =
                *((u32 *)hdl->private->reg_blks[0].vir_addr);
}
```

而这个 block 创建时的硬件地址为：

```c
reg_base = info->de_reg_base + hdl->private->dsc->rcq_ctl_offset;
block->reg_addr = reg_base;
```

对比正常的 per-display RCQ 地址计算：

```c
reg_base = de_base + DE_REG_OFFSET(offset, disp, 0x40);
```

前者缺少 `disp * 0x40`，因此固定落在 disp0 RCQ control。这是“另一路 CRTC flush
能够碰到 disp0 控制寄存器”的直接源码依据。

v1.4.8 的 `de_top_set_rcq_update()` 删除了旧版本的 `current_line > 0` fallback，
核心路径变为：

```c
do {
        local_irq_save(flag);
        if (de_top_query_de_busy_state(hdl, disp)) {
                reg_val = readl(reg_base);
                reg_val = SET_BITS(0, 1, reg_val, update ? 0x1 : 0x0);
                if (hdl->private->dfs_en) {
                        reg_val = SET_BITS(8, 4, reg_val, hdl->private->dfs_m);
                        reg_val = SET_BITS(12, 4, reg_val, hdl->private->dfs_n);
                }
                writel(reg_val, reg_base);
                local_irq_restore(flag);
                break;
        }
        local_irq_restore(flag);
        usleep_range(5, 10);
        i++;
} while (i < 10000);

return 0;
```

两版的 DE352 hardware descriptor 都没有 `.support_dfs = 1`。旧版 DFS 路径却未检查
该能力，直接执行：

```c
reg->bits.m = m;
reg->bits.n = n;
de_top_set_block_dirty(priv, DE_RCQ_CTL_REG_BLK, 1);
```

v1.4.8 先增加能力门控：

```c
if (!hdl->private->dsc->support_dfs)
        return 0;

hdl->private->dfs_en = true;
hdl->private->dfs_n = n;
hdl->private->dfs_m = m;
```

所以后三行只服务于明确支持 DFS 的其他 DE；在 DE352 上函数于门控处返回，不会写
m/n，也不会设置 `dfs_en`。再结合停用 force-by-AHB，A733 不再把共享 shadow 整块
写到 disp0 RCQ control。

两版的 A733 match data 均为：

```c
static const struct de_match_data de352_data = {
        .version = 0x352,
        .update_mode = RCQ_MODE,
};
```

所以 `rcq_wait_line` 为默认 false。A733 的 flush 直接执行 `de_top_set_rcq_update()`；
v1.4.8 新增的 adjusted timing/扫描线 page-flip 判断不会进入 DE352 分支，本文不把
它计入本机稳定性的主要原因。

这些变化共同减少旧 RCQ 错误触发窗口，但结尾仍无“10000 次均失败”的错误返回；
v1.4.8 也仍注释 `drm_atomic_helper_wait_for_vblanks()`。因此新版是强力规避/缓解
触发点，不是完整的生命周期安全修复。

### 5.3 extcon、CRTC change refresh 与 atomic mode state

extcon 本身不是 framebuffer 锁存器，也不会让两个 CRTC 共用一个 vblank。它的作用是把
外部连接/拔插状态同步给连接器消费者，并配合 DRM hotplug 重新探测、重建显示状态。这样
HDMI/外部输出发生变化时，不再只改变输出侧状态而让 CRTC/DE 继续沿用旧 mode/timing。

1.4.8 最终源码还直接新增：

```c
if (crtc_state->mode_changed || crtc_state->connectors_changed)
        drm_mode_to_sunxi_video_timings(&crtc_state->adjusted_mode,
                                        &scrtc->timings);
```

CRTC 中断随后调用：

```c
busy = sunxi_de_query_de_busy(scrtc->sunxi_de, &scrtc->timings);
```

DSI/LVDS/RGB 也从旧 `.mode_set` 改为 `.atomic_mode_set`，直接从本次
`crtc_state->adjusted_mode` 保存输出 mode。它们与 FAE 所说的“CRTC 有变化就刷新”一致：
连接状态、DRM atomic state 与 DE 时序不再长期分离。

需要保留一个源码边界：两个 BSP 最终树中都能看到受 `CONFIG_EXTCON` 控制的 HDMI/eDP
extcon 代码，因此“源码中出现 extcon”本身不是唯一版本差异。FAE 所说的“新驱动接入”
还可能包含 1.4.8 实际内核配置、设备树和用户态监听的完整接线。能够从两个最终源码树直接
确认的新增项，是 CRTC mode/connector change 时的 timing refresh 以及新的 atomic mode
capture。对 A733/DE352 而言 `rcq_wait_line=false`，所以不能把 timing-aware busy 分支单独
称为全部根因修复；它与 RCQ/DFS 改动共同保证状态一致。
### 5.4 新版扫描线判断存在，但不是 A733 的直接稳定原因

v1.4.8 确实为 `RCQ_MODE && rcq_wait_line` 平台增加了“当前扫描线 +
`ver_front_porch`”判断，并在 CRTC atomic check 中缓存 `adjusted_mode`。这段逻辑用于
vblank IRQ 判断是否应完成 page flip，防止 IRQ 已延迟到下一帧 active region 时误发
上一帧 fence/event；它不是 `de_top_set_rcq_update()` 的触发条件。

但 A733 使用的 `de352_data` 在 BSP 1.4.6 与 1.4.8 中都没有设置
`rcq_wait_line=true`；设置该标志的是 DE210。因此 A733 会继续读取通用 DE busy 位，
不会进入上述 timing 分支。DSI 从 `.mode_set` 改用 `.atomic_mode_set`、使用本次 atomic
state 的 `adjusted_mode`，有助于模式状态一致性，但不能作为本机 1.4.8 稳定的主解释。

### 5.5 HDMI 路径还有次要稳健性改进

v1.4.8 还更新了 HDMI EDID 的读取、校验和释放方式，分开保存 boot state 与实际 HPD
enable 状态，并加强输出模式选择的错误处理。这些变化可以降低 EDID 生命周期错误、
启动时 HPD 状态不一致或异常 mode list 导致的额外 modeset。

但它们不是本次硬锁的首要解释：旧日志的直接故障 master 是 DE0，且真正闭合的因果链
是 old framebuffer unmap 后仍被 scanout。HDMI 改进主要减少触发次数；停止 DE352
不支持的 DFS/共享控制寄存器写入，以及收紧 RCQ update，才直接作用于 A733 硬件是否
正确锁存新地址。

### 5.6 v1.4.8 没有完全修复生命周期安全缺口

需要避免过度结论。v1.4.8 中仍然存在：

- `sunxi_de_atomic_flush()` 返回 `void`；
- 50 ms 超时只打印日志，不能向上层返回失败；
- `sunxi_crtc_finish_page_flip()` 仍会在 flush 返回后执行；
- 自定义 commit tail 仍注释掉 `drm_atomic_helper_wait_for_vblanks()`，随后清理 old planes。

所以 T4/6.6 表现稳定更可能是因为新版 DE TOP/RCQ 和双输出时序避免了“硬件仍扫旧地址”这个触发事件，而不是 framebuffer 生命周期错误处理已经从结构上完全封死。

此外，两个 BSP 中 `sunxi-iommu-v2.c`、`sunxi_drm_gem.c`、`sunxi_drm_debug.c` 和
`de_ovl.c` 没有对应差异；`sunxi_drm_gem_fb_destroy()`、注释掉 vblank wait 后立即
`cleanup_planes()` 的关键顺序也相同。这排除了“1.4.8 只是屏蔽 IOMMU fault 或延后
unmap，所以表面看起来稳定”的解释。若新版仍生成相同 stale scanout，原来的 fault
处理链仍然存在；当前没有出现致命链，更像是错误 RCQ 地址状态不再被制造出来。

换言之：

- v1.4.8/T4 对主触发点有明显缓解或修复；
- 但如果将来在另一种边界条件下 RCQ 仍漏切，现有上层错误处理仍可能过早释放旧 FB；
- 这也是后续补丁不能只追求“不再复现”，还应补充可靠完成语义的原因。

这也解释了为什么应描述为“1.4.8 中问题几乎不存在”，而不是“1.4.8 已从形式上证明绝不可能发生”：新版显著降低了 RCQ 漏切概率，但 flush 失败上传、vblank 等待和 old-FB 保活这三层兜底仍未完整建立。目前的稳定性来自主竞态窗口被收窄，加上实际测试尚未命中剩余边界，而不是所有生命周期缺口都已消失。

### 5.7 RTMX line-buffer 不是两版判别变量

当前归档的 BSP 1.4.6 与 BSP 1.4.8 均使用无 busy 检查的静态写入：

```c
if (disp == 0)
        writel(0x2000,
               de_base + DE_REG_OFFSET(DE_BUF_DEPTH_OFFSET, disp, 0x4));
else if (disp == 1)
        writel(0x1000,
               de_base + DE_REG_OFFSET(DE_BUF_DEPTH_OFFSET, disp, 0x4));
```

两版源码对照结果相同。因此它是两版共有行为，不是解释“旧 #21 高频失败、1.4.8
几乎不失败”的差异项，也不作为首要 A/B 变量。

### 5.8 为什么可以把 1.4.8 视为工程解决方案

1.4.8 同时收紧了两类条件：

- **DE/RCQ 层：**按 `support_dfs=false` 跳过不支持的 DFS，停用固定强写 disp0 control 的
  force-by-AHB，并重写 RCQ update；
- **状态层：**extcon/hotplug 完整接线、CRTC change 时刷新 adjusted timing、输出驱动使用
  atomic mode state，并改进 HDMI boot/HPD/EDID 状态管理。

Radxa 官方屏与 Meizu E3 跨 panel 都从“1.4.6 同类故障”变为“1.4.8 稳定”，再加上本机
6.6/T4 长时间无 IOMMU/RCU 链，已经足以在工程上判断：**1.4.8 避免或解决了本次实际
触发路径。**原厂双 MIPI/LVDS 等组合的 Android 结果只作辅助参考，不承担 Linux 通用验证结论。仍需谨慎的是，1.4.8 的 `sunxi_de_atomic_flush()` 仍返回 `void`、custom tail
仍跳过标准 vblank wait，所以它更像把 DE 自有完成语义和状态刷新修到可用，而不是从形式
上加入了一层永不可能 use-after-unmap 的通用保护。

需要特别区分：FAE 所说“新驱动接入 extcon”是完整产品配置和状态链路的信息；两个最终源码树里都能找到受 `CONFIG_EXTCON` 控制的 HDMI/eDP 代码，因此不能仅凭“源码中出现 extcon”判断版本。能直接从源码确认的新增关键行为，是 CRTC mode/connector change 时刷新 timing，以及输出侧改用本次 atomic mode state；它们与 DE/RCQ 修正共同生效。

## 六、Android 同样走 DRM，为什么 Android 测试较少暴露

Android 与 X11 都能调用 DRM atomic，但上层提交和 buffer 生命周期不同。

Android 的 SurfaceFlinger/HWC 为每个物理 display 执行 validate/present，使用 acquire、
release 和 present fence 管理 buffer。release fence 的定义就是“旧 buffer 已不再被 HWC/
显示使用”之后才能交回 producer；常见 drm_hwcomposer 还会等待上一帧 present fence，再
清理上一帧资源。BufferQueue/gralloc 通常维护可循环复用的双/三缓冲池，而不是在每一次
桌面交接后立即销毁整个物理 framebuffer 对象。

因此旧 DRM 即使偶尔漏掉一次 RCQ update，在 Android 上更可能表现为：

- 旧 gralloc buffer 仍有 SurfaceFlinger/HWC/BufferQueue 引用，IOVA 仍合法；
- 多显示一帧旧内容，下一次 present/RCQ 可能自愈；
- buffer 被归还池中等待复用，而不是马上 RMFB 并解除映射；
- 已知 Android 双 MIPI、LVDS 测试中的部分拓扑没有进入本机的 LCD+TV 混合事务；这只能
  解释特定 Android 现象，不能证明同类 LCD-TCON 在其他用户态普遍正常。Android 产品路径
  还缺少本机 HDMI+SDDM→Plasma 的动态重建窗口。

X11/Plasma 本次则确实销毁了 3000×2160 old FB；驱动日志记录 `map:0/unmap_ts` 后，DE0
继续访问它。也就是说 Android 稳定主要是**没有把潜伏的地址漏切升级为 use-after-unmap**，
而不是 Android 绕过了 DRM 或证明旧驱动没有缺陷。即使 Android 的 fence 被错误地提前
signal，长期 gralloc buffer pool 仍可能让地址保持映射，只产生短暂旧帧而不触发 IOMMU。

这部分关于 Android 通用 fence/BufferQueue 语义由 AOSP 文档和 drm_hwcomposer 实现支持；
工作区没有原厂具体 HWC 源码，因此“其实际 HWC 是否逐帧等待哪个 out-fence”不能写成已
核实事实。同类 TCON 拓扑、buffer pool 与无 SDDM 会话切换可以合理解释复现率降低，但前者
只在 Android 测试范围内有现象支持，不能提升为原厂通用确认。

因此应按优先级解释：

1. **首要原因是用户态提交窗口不同。**Android 没有 SDDM→Plasma 的整套 root-FB 销毁和布局重建。
2. **拓扑差异是范围受限的解释。**已有 Android 双 MIPI/LVDS 现象主要涉及同类 LCD-TCON，没有进入本机 LCD+TV 事务；这不是 Linux/Debian 普遍稳定性证明。
3. **buffer 生命周期具有掩蔽作用。**HWC/BufferQueue/fence 往往让旧 gralloc buffer 保持映射更久，可能把漏切表现降级为旧帧而不是立即 IOMMU fault。

## 七、GPU、背光、触摸及其他相邻现象

### 7.1 GPU 的角色

GPU 和 DE/DRM 的职责需要分开：

1. GPU/PVR 根据 KWin、Xorg、应用的命令绘制窗口内容到 buffer。
2. DRM/KMS 把某个 buffer 选为 framebuffer/plane。
3. DE 从该 framebuffer 的 DMA 地址读取像素，送到 DSI 或 HDMI。

GPU 可以通过动画、合成和双屏布局增加 buffer 轮换和 atomic commit 的频率，因此它能成为“触发负载”。但即使 GPU 提交得再快，内核 DRM 也必须保证 DE 不再使用 old FB 后才能解除其映射。

当前反对 GPU 为主根因的证据：

- 旧系统和 T4 都报告 PVR `24.2.6603887`、BVNC `36.56.104.183`。
- 硬锁日志中出错的 IOMMU master 是显示引擎 `DE0`，不是 GPU master。
- 故障地址与 DRM scanout framebuffer 的 map/unmap 追踪吻合。
- T4 上的 EGLConfig/KWin compositor 异常能造成拖影或残帧，但没有产生 DE IOMMU fault → RCU stall 链。

因此应把两类问题分开：

- T4 的拖影：更像用户态 EGL/KWin 合成路径失效，画面难看但内核仍运行。
- 旧 5.15 的硬锁：DE 读取已解除映射的 scanout，引发 IOMMU 中断风暴和 RCU stall。

### 7.2 已被受控实验确认

1. `reg = <1>` 是遵循官方 A7A DSI graph 的必要修正，且它能正常驱动面板；它不是运行期硬锁根因。
2. 背光、触摸和面板初始化不是本次 hard lock 的根因。
3. 主根因属于旧 sunxi DRM/DE，而非 PVR GPU 内核驱动。
4. 两屏冻结是一个共享 DE/IOMMU/调度故障，不要求 DE1 自己也报告页表错误。
5. 每次卡死在不同屏幕页面或不同串口最后一行，是异步竞争和整机中断/RCU 失速的外部表现。

### 7.3 被受控实验收窄或修正

1. 不能再把历史上所谓“DSI-only 卡死”当成有效单 DSI 证据；当时有错误拓扑、残留 workaround 或其他 DTS 变量。本轮严格单 DSI 连续通过。
2. 双屏本身不是充分条件；桌面后热插双屏可稳定运行。
3. 最危险路径是 HDMI 开机存在时，从 SDDM 切到 Plasma 所引发的双 CRTC/FB 重配置。
4. `atomic_flush timeout` 不是必要前兆；最核心事实是旧 framebuffer 在 unmap 后仍被 DE 使用。
5. 首次主动 DSI off/on 的 `displl clk unable to lock` 是另一处时钟切换脆弱性，但它成功恢复且没有进入 stale-FB/IOMMU 链，不能解释本次登录硬锁。

### 7.4 其他现象不能混入硬锁根因

- **背光偶尔很低或延迟点亮：**属于 SGM37604A 供电、初始化时序、默认亮度或桌面亮度状态问题。它会影响可见性，但不能制造 DE0 对已 unmap IOVA 的读取。现有证据不足以把低亮度进一步归到某一个唯一子原因。
- **触摸坐标或鼠标不在手机屏：**属于输入驱动与 X11 输出映射。决定性硬锁实验没有加载触摸，故它不在因果链中。
- **T4 窗口拖影：**属于 GPU/EGL/KWin 重绘或合成问题；没有 IOMMU/RCU 链，系统仍可交互。
- **黑屏但有鼠标、蓝色/灰白画面：**可能是登录交接中 scanout、合成器或 modeset 的不同中间状态；只有同时出现 DE IOMMU fault/RCU stall 时，才能归入本篇硬锁。
- **心跳灯熄灭、SSH/串口业务停止：**是 IRQ 风暴和 RCU 饥饿后的整机后果，不是第二个独立电源或网络故障。

## 八、下一步验证与修复策略

后续不要再改面板初始化、I²C、触摸或背光。保持当前 `v001-reg1` overlay 和已验证的 SGM 背光，把变量限定在旧内核 DRM/DE 源码。

结合 v1.4.6/v1.4.8 最终源码快照，建议按以下顺序验证。每一步单独构建、保留 `l0r` rescue，并在 HDMI 开机连接条件下做至少 10～20 次冷启动登录：

1. **B1：只给旧版 `de_top_freq_div_apply()` 加 `support_dfs` 检查。** DE352 直接返回而不 dirty RCQ-control shadow；这是最小、最贴合 SoC 能力声明的单变量修正。
2. **B2：只停用 `de_top_update_force_by_ahb()`。** 这是旧 #21 与 BSP 1.4.8 最明确、且已在 #21 二进制中确认旧行为存在的差异；用于区分“错误 DFS dirty”与“整寄存器 AHB 强写”各自贡献。
3. **B3：只采用新版 RCQ 触发条件。** 删除 `current_line > 0` 时的整寄存器 `writel(1)` fallback，始终在确认 DE busy 条件后执行 read-modify-write。B1、B2、B3 先分别测试，再做组合测试。
4. **D：补齐生命周期保护。** 让 RCQ flush 返回真实成功/失败；只有确认 update/至少一个可靠 vblank 后才完成 page flip 和释放 old FB。恢复等待时要注意多 CRTC deadlock/timeout 设计，不能仅机械取消注释。
5. **增加只读追踪。** 对每个 CRTC 记录：atomic 序号、old/new FB DMA、DFS m/n、RCQ request、finish status、current line、vblank counter、实际 OVL address register readback、FB destroy/unmap 时间。
6. **C：RTMX 动态 line-buffer 仅作为低优先级实验。** 因为 BSP 1.4.6 与 BSP 1.4.8 最终源码都采用静态实现，它不再是解释两版差异的判别变量；只有在 B1～B3 仍无法降低复现率时才单独测试。

判定标准不能只看“画面亮了”，应同时要求：

- 串口无 PageTable Invalid；
- 无 `sunxi_de_atomic_flush timeout`；
- 无 RCU stall；
- DE0/DE1 debug `err=0`；
- SDDM → Plasma 登录、注销、再次登录均通过；
- 冷启动双屏 10～20 次无复现；
- 单 DSI 和桌面后热插 HDMI 不发生回归。

如果 B1 单项有效，说明根因核心是不支持 DFS 的 DE352 被错误 dirty；如果 B2 单项有效，说明 force-by-AHB 整寄存器/跨 display 覆盖更关键；如果 B3 单项有效，说明 current-line fallback 是主要漏切窗口。若只有组合有效，则说明稳定性来自三项 RCQ 控制行为共同收敛。如果这些改动只能降低概率，而 D 才完全消除 stale-FB，则说明新版主要是规避触发，真正安全修复仍必须落在完成语义和 framebuffer 保活上。

产品路径的优先级高于定位最小补丁：实际部署应使用 1.4.8 新 DRM；B1/B2/B3 仅用于解释旧 1.4.6 的最小故障机制。任何旧内核实验都必须保留无测试 overlay 的 `l0r` rescue 项，并通过串口确认菜单。

## 九、证据与源码索引

### 9.1 决定性日志

- 冷启动 HDMI+DSI 登录硬锁：`test_files/mainline/06_old_kernel_dual_display_crosscheck/log/serial-COM4.log`
- 旧 framebuffer `map:0/unmap_ts` 后仍被扫描：`test_files/codexline/02_rk_reference_pushpull_validation/log/serial-v003-boot.log`
- 实验说明：`test_files/mainline/06_old_kernel_dual_display_crosscheck/docs/cold-boot-login-freeze.analysis.md`

### 9.2 关键旧 BSP 源码

- plane/CRTC：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_crtc.c`
- OVL 地址：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_device/hardware/lowlevel_de/ovl/de_ovl.c`
- DE flush：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c`
- DE TOP/RCQ：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_device/hardware/lowlevel_de/de_top.c`
- TCON：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_device/sunxi_tcon.c`
- atomic tail/FB destroy：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_drv.c`
- FB trace/GEM：`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_debug.c`、`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_gem.c`
- IOMMU：`bsp/radxa-allwinner-bsp/drivers/iommu/sunxi-iommu-v2.c`
- A733 拓扑：`bsp/radxa-allwinner-bsp/configs/linux-5.15/sun60iw2p1.dtsi`

### 9.3 新版与标准 DRM 对照

- BSP 1.4.8 同路径源码：`bsp/radxa-allwinner-bsp-v1.4.8/`
- Linux DRM helper：`bsp/radxa-kernel-a733/drivers/gpu/drm/drm_atomic_helper.c`
- 上游来源、分支与固定 commit：`BSP_PROVENANCE.md`

## 十、最终工程判断

这次适配已经证明 Meizu E3 panel、官方 graph 方向、背光和触摸可以在 A733 上工作。旧系统的致命问题不在面板，而在 BSP 1.4.6 试用版 DRM 处理 `TCON-LCD + TCON-TV` 双 CRTC 登录重配置时，DE/RCQ 实际锁存、complete 语义与 framebuffer 生命周期没有形成可靠闭环。X11 销毁旧 root framebuffer 后，DE0 继续读取已解除映射的地址，IOMMU 中断风暴最终拖死 RCU。

原厂 FAE 信息不是推翻这条结论，而是把范围进一步限定清楚：DE 自有 complete 是设计前提，错误在于旧版没有保证 complete 与真实 scanout 交接一致；extcon/CRTC 刷新是新版状态一致性的一部分；1.4.6 的 Android 验证没有覆盖本机 Debian+X11 混合 TCON 的高风险事务。BSP 1.4.8 通过 DE352 DFS/RCQ 修正和输出状态刷新共同避开了实际故障链，因此是当前正确的产品基线。
