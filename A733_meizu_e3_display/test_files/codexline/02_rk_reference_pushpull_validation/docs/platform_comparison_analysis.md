# Meizu E3 / Radxa Display 8HD 在 RK3576 与 A733 上的四象限分析

时间：2026-07-31 15:42（Asia/Shanghai）

本轮只做资料、源码和既有日志分析，没有连接或修改开发板。

## 1. 分析对象

四种组合：

1. Meizu E3 手机屏 + RK3576 ROCK 4D（社区可用参考）
2. Meizu E3 手机屏 + Allwinner A733 Cubie A7A（本项目 v001/v002）
3. Radxa Display 8HD + RK3576 ROCK 4D（Radxa 官方）
4. Radxa Display 8HD + Allwinner A733 Cubie A7A（Radxa 官方）

主要本地证据：

- `radxa-meizu-e3/rk3576-rock-4d-panel.dtsi`
- `radxa-meizu-e3/sgm37604a.c`
- `radxa-meizu-e3/sec_ts/`
- `radxa-overlays-official/arch/arm64/boot/dts/rockchip/overlays/rock-4d-radxa-display-8hd.dts`
- `radxa-overlays-official/arch/arm64/boot/dts/allwinner/overlays/cubie-a7a-radxa-display-8hd.dtso`
- `test_files/mainline/01_initial_overlay_validation/`
- `test_files/codexline/01_nonburst_dsi_experiment/`
- `test_files/codexline/02_rk_reference_pushpull_validation/docs/rk_reference_analysis.md`

官方在线源码：

- RK3576 8HD overlay：
  https://github.com/radxa-pkg/radxa-overlays/blob/main/arch/arm64/boot/dts/rockchip/overlays/rock-4d-radxa-display-8hd.dts
- A733 8HD overlay：
  https://github.com/radxa-pkg/radxa-overlays/blob/main/arch/arm64/boot/dts/allwinner/overlays/cubie-a7a-radxa-display-8hd.dtso
- RK 8HD 专用面板驱动：
  https://github.com/radxa/kernel/blob/linux-6.1-stan-rkr5.1/drivers/gpu/drm/panel/panel-radxa-display-8hd.c
- A7A DSI graph 官方修复：
  https://github.com/radxa-pkg/radxa-overlays/commit/4349013e00f21b703a75d620d8589f301ffc0493

版本与 SHA256 固定如下，避免以后仓库更新造成对比漂移：

```text
radxa-overlays commit:
c79b70822a314a7c828d361cbe976780af45c0a3

radxa RK kernel branch commit:
bf385fa8f017f6c3575b18788e73f204281af737

435bfe99a098443cff88336d8157fff8649f00db4ec69da757ea454b4e912e54
  rock-4d-radxa-display-8hd.dts
e1df74fb19c2b5fe5a039c74df98b9b7d245d74970b225265f97aeec72bc2585
  cubie-a7a-radxa-display-8hd.dtso
dcb3d099f9e60362cd9c10bd889d23ae95b25040f25fafd028232984ab9368c3
  rk3576-rock-4d-panel.dtsi
762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e
  cubie-a7a-meizu-e3-display-v001.dtso
8459223cec0ca1fbe7036aa33fedf69529e20292941d4d26c67caa6a4f6c2b13
  cubie-a7a-meizu-e3-display-v002.dtso
```

## 2. 四象限精确对比

| 项目 | Meizu / RK3576 | Meizu / A733 v001 | Radxa 8HD / RK3576 | Radxa 8HD / A733 |
|---|---|---|---|---|
| 来源性质 | 社区成功适配，用户称 RK 上可完整使用 | 本项目翻译版，非官方屏 | Radxa 官方 | Radxa 官方 |
| 面板框架 | `simple-panel-dsi` | `allwinner,panel-dsi` + `allwinner,virtual-panel` | 专用 `panel-radxa-display-8hd.c` | `allwinner,panel-dsi` + `allwinner,virtual-panel` |
| 分辨率/像素时钟 | 1080×2160 / 157 MHz | 1080×2160 / 157 MHz | 800×1280 / 70 MHz | 800×1280 / 70 MHz |
| 原始 RGB888 数据率 | 约 942 Mb/s/lane | 约 942 Mb/s/lane | 约 420 Mb/s/lane | 约 420 Mb/s/lane |
| DSI flags | VIDEO + BURST + LPM + NO_EOT + CLOCK_NON_CONTINUOUS，即 `0xe03` | v001 为 VIDEO + BURST + LPM + NO_EOT，即 `0xa03`；v002 为 `0xa01` | 驱动内设 VIDEO + BURST + NO_EOT，即 `0x203` | 仅 VIDEO，即 `0x001` |
| lane rate | 由 RK DSI 主机推导 | 由 sunxi DSI/combophy 推导 | overlay 显式 480 Mb/s | 未在 overlay 中显式给定 |
| 垂直同步宽度 | 2 | 4 | 4 | 4 |
| 水平 porch | HFP 115 / HBP 13 / HS 3 | 同左 | HFP 40 / HBP 20 / HS 18 | HFP 18 / HBP 18 / HS 18 |
| 退出序列 | display-off 后 16 ms；sleep-in 后 120 ms | 两处都是 0 ms | 驱动发送 display-off、sleep-in；unprepare 前等待 120 ms | 两处都是 0 ms |
| LCD reset | 推挽，DT active-low；完整 prepare/reset 延时 | PD19 active-high + **open-drain**，且转接板未见外部上拉 | 推挽 GPIO | PD21 active-high，推挽 |
| 背光 | 面板直接绑定 SGM37604A；SGM 驱动手机屏 LEDA/LEDK | 面板绑定从 8HD 模板复制来的 PWM；SGM 作为另一套独立 backlight | PWM，GPIO enable | PWM，GPIO enable |
| 触摸/背光总线 | RK 硬件 I²C0；SEC@0x48、SGM@0x36 | 新建 `i2c-gpio`；SEC@0x48、SGM@0x36 | RK 硬件 I²C0；Goodix@0x14 | A733 官方硬件 `twi2`；Goodix@0x14 |
| DSI 路由 | DSI -> VP1；HDMI -> VP0 | DE0/TCON0 -> DSI；HDMI 实测走 DE1/TCON3 | DSI -> VP1；HDMI -> VP0 | 官方 A733 graph，包含修复后的 `port@1 reg=1` |

数据率只表示有效 RGB 数据：

```text
8HD:   70 MHz × 24 bit / 4 lane = 420 Mb/s/lane
Meizu: 157 MHz × 24 bit / 4 lane = 942 Mb/s/lane
```

RK 8HD 显式使用 480 Mb/s，说明其 420 Mb/s 有效数据之外还留有协议/消隐余量。
Meizu 的基础负荷已是 8HD 的约 2.24 倍；Allwinner burst 分支还会按源码对内部
有效 pixel clock 做 `10/9` 调整，因此不能因为 A733 官方 8HD 使用 non-burst，
就推导出 157 MHz 的 Meizu 也应去掉 burst。

## 3. 从 Radxa 8HD 跨平台适配得到的正确规则

同一块 Radxa 8HD 在两个平台上并没有逐字相同的 DTS：

- RK 使用专用面板驱动，驱动内设置 burst + no-EOT；overlay 又显式设置
  480 Mb/s lane rate。
- A733 使用全志的 virtual-panel/panel-dsi 框架，官方配置只设置 VIDEO，
  时序 porch 也和 RK 版本不同。
- 两端的面板初始化由不同载体提供：RK 放在 C 驱动中，A733 放在 DTSO 中。
- 但同一屏的硬件身份没有变：仍是 PWM 背光、Goodix 触摸、固定的供电和复位
  网络。平台改变不会把 PWM 屏变成 SGM 背光屏。

由此必须把参数分成两类：

### 3.1 平台合同：必须跟随 A733 官方实现

- `allwinner,virtual-panel` / `allwinner,panel-dsi`
- DSI0、combo-PHY、DLCD0、TCON 的官方 graph
- 官方 `port@1 reg=<1>` 修复
- A733 的硬件 `twi2`、pinctrl、supply、`twi_drv_used`、`no_suspend`
- A733 panel 驱动对 reset logical 0/1 和 DSI flags 的解释

### 3.2 屏幕合同：必须来自 Meizu 成功参考和转接板电路

- 1080×2160、157 MHz 和精确 porch/sync
- sleep-out/display-on、display-off/sleep-in 以及各自延时
- 4 lane RGB888
- SGM37604A 是真正的 LED 背光控制器
- SEC 是真正的触摸控制器
- LCD_RESET 是无外部上拉的直连网络，必须有确定的推挽电平
- Meizu 已知成功方案要求的 burst、LPM、NO_EOT、non-continuous clock

当前 v001 的核心设计问题，就是把两类合同混合了：

- 平台 graph 基本采用了 A733 官方结构，这是正确部分。
- 却复制了 8HD 的 PWM backlight 生命周期，而实际 LED 由 SGM 驱动。
- 复制了 A733 8HD 的 `vsync=4` 和 exit 零延时，而 Meizu 参考是
  `vsync=2`、16/120 ms。
- 没有采用 A733 官方硬件 `twi2`，而是创建 `i2c-gpio`。
- reset 额外增加了两份成功参考都没有的 `GPIO_OPEN_DRAIN`。
- v001 又遗漏 Meizu 参考中的 CLOCK_NON_CONTINUOUS；v002 则进一步把
  8HD/A733 的 non-burst 误套给了高两倍带宽的 Meizu。

所以，v001/v002 不是“Radxa 官方 A733 8HD 模板的完整 Meizu 翻译”，而是一个
能偶尔初始化、但生命周期不闭合的混合配置。

## 4. 既有现象和日志的统一解释

### 4.1 为什么冷启动概率性亮屏

首要证据指向 reset 电气，而不是 graph：

- v001 至少有一次完整走到 `DSI-1: Configuration complete`，LightDM 双屏正常，
  证明 overlay 被加载、graph 能绑定、157 MHz burst 路径能够启动。
- 当前 LCD_RESET 被声明成 open-drain；驱动最终把它设置为逻辑高时，物理上只是
  释放线路。
- 转接板网表中 LCD_RESET 是连接器到面板的直连网络，未发现离散上拉。

因此 reset 释放的高电平、上升沿和到达阈值的时间会依赖 SoC 内部上下拉、寄生
电容、漏电和上一次上电状态。这正好表现为有时立即亮、有时很久后亮、有时不亮。

次要概率源是 SGM/SEC 走软件 `i2c-gpio`，同时 DKMS 驱动较晚 probe；日志中已经
出现 SGM `reg 0x11` 读回不符、SEC 写失败和两者 `-EIO`。

### 4.2 为什么亮度有时很低

当前同时存在两套互不闭合的背光对象：

```text
panel -> PWM backlight (8HD 模板)
SGM37604A -> 实际手机屏 LEDA/LEDK（却没有绑定到 panel）
```

面板 enable/disable 控制的是 PWM 对象，而物理 LED 亮度由另一套 SGM 寄存器和
HWEN 决定。SGM probe 又可能失败，暖重启时还可能保留部分寄存器状态，所以会出现
默认值、旧值、低亮值或偶然恢复。它不是一个单纯的 Plasma 亮度滑块问题。

### 4.3 为什么 LightDM 正常，进入 Plasma 后两屏一起异常

完整时间证据：

```text
LightDM：HDMI + DSI 都能正确显示
约 112.923 s：Plasma/显示重配后第一个 sunxi_de_atomic_flush timeout
112.923–119.389 s：至少 116 次 atomic flush timeout
119.503 s：第一个 IOMMU fault，地址 0xfae77000
119.527 s：继续访问已解除映射的 0xfa000000
随后：IOMMU IRQ storm -> RCU stall -> SSH/心跳/整个系统失去响应
```

这证明硬锁的直接机制不是触摸或背光驱动，而是：

```text
第二次 atomic modeset/DPMS
  -> DE RCQ/atomic flush 未完成
  -> 驱动仍向上层推进 page flip / 解除旧 framebuffer 映射
  -> DE0 继续扫描旧地址
  -> IOMMU fault 中断风暴
  -> RCU 被饿死，系统表现为随机位置卡住
```

Meizu exit sequence 在 v001 中没有 16/120 ms，恰好不会影响第一次上电，却会影响
LightDM -> Plasma 这种 disable/unprepare/re-enable。它很可能是触发 DE timeout 的
面板侧条件之一；全志 DE/IOMMU 的错误恢复缺陷则把一次显示超时放大成整机硬锁。

HDMI 与 DSI 并没有被设备树“合成同一路”。日志表明 DSI 使用 DE0/TCON0，HDMI
使用 DE1/TCON3；但两者属于同一个 sunxi DRM atomic 设备并共享 DE/IOMMU master，
所以一次未返回或失败的 atomic commit 可以让两路都没有有效画面。

每次串口最后一行不同也不代表有很多互不相关的死机原因。多核系统中显示提交、
桌面进程、网络、Wi-Fi、RCU 和中断并行运行；IOMMU fault storm 出现后，哪个 CPU
最后来得及打印哪一行具有随机性。真正稳定重复的指纹是 atomic timeout、
`0xfa000000`、IOMMU fault 和随后的 RCU stall。

### 4.4 v002 为什么两屏从启动就黑

v002 唯一功能变量是删除 burst：

```text
v001 flags = 0xa03
v002 flags = 0xa01
```

v002 日志停在：

```text
1.842307  CRTC atomic enable
1.843107  sunxi_dsi_combophy_configure start
之后没有 lowlevel timing、encoder enable finish、DSI Configuration complete
```

同一位置 v001 能继续完成 DSI 配置。因此 v002 已经是严格 A/B 失败，不应再把
“A733 8HD 使用 non-burst”当成 Meizu 的修改方向。DSI enable 没有返回时，同一
DRM atomic commit 中的 HDMI 也无法得到完整画面。

## 5. 根因排序

### 高置信度、已经有直接证据

1. **整机硬锁的直接机制**：A733 vendor DE atomic flush 失败后，旧 framebuffer
   已解除 IOMMU 映射但 DE0 仍访问；IOMMU IRQ storm 最终造成 RCU stall。
2. **v002 黑屏原因**：删除 burst 后，Meizu 157 MHz 路径卡在 combo-PHY/encoder
   初次 enable；v002 已被日志否决。
3. **概率性初始化的主要电气问题**：无外部上拉的 LCD_RESET 被配置为
   open-drain。
4. **亮度漂移的结构问题**：panel 绑定 PWM，但实际 LED 由未绑定的 SGM 控制。

### 中高置信度、需要下一版验证

5. **桌面切换触发条件**：Meizu 的 exit 16/120 ms 被错误改成 0/0，且 vsync 由
   2 改成 4；这两项和首次上电无关，却正好影响 Plasma 第二次 modeset。
6. **辅助总线不稳定**：软件 `i2c-gpio` 偏离 RK 成功参考和 A733 官方 8HD 两端
   都使用硬件控制器的做法，与 SGM/SEC `-EIO` 对应。
7. **持续时钟差异**：v001 少了 Meizu RK 参考明确要求且 A733 驱动支持的
   CLOCK_NON_CONTINUOUS。它可能影响运行期链路稳定性，但不是 v002 卡在
   combo-PHY 的解释，必须在前述错误修正后受控验证。

### 当前证据不支持

- 不是 U-Boot 没有加载 DTBO：v001 LightDM 双屏和 DSI configuration complete
  已证明加载成功。
- 不是 HDMI、DSI 被接到同一 CRTC。
- 不是触摸或 SGM 调用栈直接造成 DE/IOMMU fault。
- 不是看到 RCU 日志就说明 RCU 本身是最初原因；在已保存现场中 RCU 是中断风暴
  之后的结果。
- 不是“单独 DSI 天生不支持”或“必须 HDMI 陪同才能启动”；偶尔双屏可用只是竞态
  尚未触发，不是正确性的证明。

## 6. 下一步：先建立对照，再制作 v003

### 阶段 0：保持当前安全基线

- 当前板端继续保持零 active overlay。
- `l0` 与 `l0r` 都不手工编辑；所有启用/禁用经 rsetup 底层机制和
  `u-boot-update` 生成。
- `l0r` 保持 stock、`single`、无 Meizu overlay。
- 每个版本保留源码、预处理 DTS、DTBO、readback、SHA256、extlinux 前后状态和
  完整串口日志。

### 阶段 1：如果手头有 Radxa 8HD，先做官方控制实验

在同一块 A7A、同一内核、同一 HDMI、同一 Plasma 下，只启用官方
`cubie-a7a-radxa-display-8hd.dtbo`：

- 若官方 8HD 能连续冷启动、反复登录/退出和双屏 modeset，说明 A733 双显示主路径
  可用，焦点应放在 Meizu 合同翻译。
- 若官方 8HD 也复现相同 `sunxi_de_atomic_flush timeout -> IOMMU fault`，则可把
  面板种类排除，直接定位为当前 A733 内核/DRM 双 CRTC 缺陷；此时不再修改 Meizu
  flags。

没有实体 8HD 时跳过，不能用静态源码代替物理 A/B。

### 阶段 2：先验证 Meizu 辅助硬件，不启用 DSI

制作独立 `v003-io` overlay，只做：

- 使用官方 A733 `&twi2` 拓扑；
- 挂接 SGM37604A@0x36 与 SEC@0x48；
- 使用转接板确认的 HWEN/IRQ GPIO；
- 不启用 DSI graph，不改变 HDMI。

通过条件：

- 多次冷启动两设备都稳定 probe；
- SGM 不再出现 `reg 0x11` 读回失败或 `-EIO`；
- SEC 不再出现 I²C write `-EIO`；
- backlight class 中只有可解释、可控的对象；
- 触摸原始坐标稳定，映射问题留给用户空间处理。

### 阶段 3：制作完整 Meizu `v003-display`

结构原则是“官方 A733 平台外壳 + Meizu 精确屏幕合同”：

1. 原样保留 A733 官方 DSI/virtual-panel/DLCD/TCON graph 和
   `port@1 reg=<1>`。
2. 恢复 v001 已证明能完成初次 enable 的 burst，永久否决 v002 non-burst。
3. 保留 4 lane、RGB888、1080×2160、157 MHz。
4. 恢复 Meizu 的 `vsync-len=2`。
5. 恢复 exit sequence 的 16/120 ms。
6. 删除 LCD_RESET 的 `GPIO_OPEN_DRAIN`；按照 Allwinner 驱动现有最终逻辑高语义
   保持推挽，不机械复制 RK `GPIO_ACTIVE_LOW`。
7. 删除 8HD PWM backlight 链，面板直接绑定 `sgm37604_bl`。
8. 使用阶段 2 已验证的硬件 `twi2`。
9. 加入 Meizu 成功参考明确要求、A733 驱动明确支持的
   CLOCK_NON_CONTINUOUS；其效果单独记录。
10. 不改 sunxi DRM、DSI、IOMMU 内核驱动。

先离线执行 `dtc`、`fdtoverlay` 合并、反编译 readback、graph 双向闭合校验和 GPIO
冲突检查，产物通过后才部署。

### 阶段 4：按故障层级测试，不直接进入双屏 Plasma

建议门槛：

1. 串口全程记录，做至少 10 次真正断电冷启动，统计：
   - DSI configuration complete 时间；
   - SGM/SEC probe 结果；
   - 初始亮度；
   - 是否存在 DSI FIFO/PHY/timeout。
2. 先只让 DSI 承担桌面输出，执行至少 20 次 DPMS off/on 或等价 modeset；
   每次统计 `sunxi_de_atomic_flush timeout`、IOMMU fault 和 RCU stall。
3. 单 DSI 稳定后才接入 HDMI，明确配置两个独立输出，再重复 LightDM -> Plasma、
   分辨率/位置切换和 DPMS 测试。
4. 任意一次出现 atomic timeout 就停止该轮，不等待它发展成 IOMMU storm；
   从 `l0r` 回滚并保存前一 boot 的 journal。

通过标准不能是“这次亮了”，而应是：

```text
10 次冷启动均初始化
亮度一致且由 SGM 唯一控制
触摸 probe 无 I²C 错误
20 次 modeset/DPMS 无 atomic timeout
双屏登录无 IOMMU fault、无 RCU stall
```

### 阶段 5：何时停止改 DTSO

若 v003 已满足精确屏幕合同，但单 DSI 或官方 8HD 控制实验仍出现同一
`sunxi_de_atomic_flush timeout -> stale framebuffer -> IOMMU fault`，就说明
overlay 已不再是主矛盾。下一步应：

- 在 Radxa 更新的 A733 内核上复测；
- 向 Radxa 提交可复现串口、boot ID、DTBO hash、DRM state 和时间线；
- 对比新版 BSP 的 DE atomic flush、page-flip 完成和 IOMMU fault recovery。

这时不再继续随机改 flags、porch 或延时，也不在当前稳定性未知的内核上和驱动
“硬刚”。

## 7. 最终判断

当前不是一个单点故障，而是三层问题叠加：

```text
Meizu A733 屏幕合同翻译不完整
  ├─ reset 开漏无上拉 -> 概率性初始化
  ├─ PWM/SGM 双背光 -> 低亮/亮度漂移
  ├─ i2c-gpio -> SGM/SEC -EIO
  └─ exit 延时/vsync/clock mode 偏差 -> modeset 风险
          ↓
Plasma 第二次 atomic modeset 触发 DE flush timeout
          ↓
A733 vendor DE/IOMMU 错误恢复缺陷
  -> stale framebuffer
  -> IOMMU IRQ storm
  -> RCU stall / 整机硬锁
```

因此下一步的正确重点不是继续试一个新 flag，而是先用官方 8HD 做平台控制实验
（若有实物），再把 Meizu 的平台合同与屏幕合同彻底拆开，按 `v003-io`、
`v003-display`、单 DSI、最后双屏的顺序验证。
