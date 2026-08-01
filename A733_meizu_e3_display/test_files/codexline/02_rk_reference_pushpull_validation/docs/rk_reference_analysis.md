# Meizu E3：RK3576 社区适配、Radxa 官方 RK 适配与 A733 现有方案对比

日期：2026-07-31

本轮只做本地资料、官方仓库和既有日志的静态分析，没有连接或修改开发板。

## 1. 对比对象

- Meizu E3 社区 RK3576 适配：
  - `radxa-meizu-e3/rk3576-rock-4d-panel.dtsi`
  - `radxa-meizu-e3/sgm37604a.c`
  - `radxa-meizu-e3/sec_ts/`
  - `radxa-meizu-e3/armbian编译补丁/0004..0006`
  - `radxa-meizu-e3/ProDoc_Board2_2026-02-07.epro2`
- Radxa 官方 ROCK 4D overlay：
  - `radxa-overlays-official/arch/arm64/boot/dts/rockchip/overlays/rock-4d-radxa-display-10fhd.dts`
  - Radxa `linux-6.1-stan-rkr5.1` 的 `rk3576-rock-4d.dts`
- Radxa 官方 Cubie A7A overlay：
  - `radxa-overlays-official/arch/arm64/boot/dts/allwinner/overlays/cubie-a7a-radxa-display-10fhd.dtso`
  - 官方 graph 修复提交 `4349013e00f21b703a75d620d8589f301ffc0493`
- 已测试 A733 候选：
  - v001 burst
  - v002 non-burst

关键输入文件 SHA256：

```text
dcb3d099f9e60362cd9c10bd889d23ae95b25040f25fafd028232984ab9368c3  rk3576-rock-4d-panel.dtsi
23c46c097c79777cbd4004c85e7c34cebac3ebefa4d70a1e10aa0f6857b0b08b  community sgm37604a.c
15112647fbb9731319c8e594247adb9b64394681f6945380c80503d8311e5f0c  ProDoc_Board2_2026-02-07.epro2
7cdcbcfbfe1fe195e89bc8773f558a92dd0e43ae9ff875849c1c5c26b7b3462f  official ROCK 4D 10FHD overlay
af039b699f4487e41240d9437b65b771ece84ade0691bf58b77c501df934e5f1  official A7A 10FHD overlay
762e7511ad78c39844b2396298e38a2a1c789e486f2c83397acc10ce953cc74e  A733 v001 source
8459223cec0ca1fbe7036aa33fedf69529e20292941d4d26c67caa6a4f6c2b13  A733 v002 source
```

## 2. 三种实现的结构差异

| 项目 | Meizu E3 / RK3576 成功方案 | Radxa 官方 ROCK 4D 方案 | 当前 A733 v001/v002 |
|---|---|---|---|
| 面板框架 | `simple-panel-dsi` | `simple-panel-dsi` | `allwinner,virtual-panel` + `allwinner,panel-dsi` 两级结构 |
| DSI 路由 | 明确 `DSI -> VP1` | 启用 `dsi_in_vp1`；RK3576 基础 DTS 已把 DSI route 默认连到 VP1 | `DE0 -> TCON0 -> DSI0`；HDMI 实测使用 DE1/TCON3 |
| HDMI 路由 | 基础 DTS 明确 `HDMI -> VP0` | 同左 | HDMI 和 DSI 属于同一个 sunxi DRM/DE 设备，但运行时使用两个 CRTC |
| I²C | SoC 硬件 `i2c0` | SoC 硬件 `i2c0` | 新建 `i2c-gpio`，在 PD16/PD17 上软件模拟 |
| 背光 | 面板的 `backlight` 直接指向 SGM37604 | 标准屏直接指向 PWM backlight | 面板指向 PWM backlight；SGM37604 是另一个未绑定的 backlight |
| 驱动装载 | SGM 和 SEC 驱动编入内核/内核模块体系 | 对应官方驱动体系 | DKMS 外部模块，加载时序更晚 |
| 面板复位 | 推挽 GPIO；DT 标记 active-low | 推挽 GPIO | active-high + `GPIO_OPEN_DRAIN` |

RK 的 `simple-panel-dsi` 节点不能直接复制到 A733，因为 Allwinner BSP 的
panel、virtual-panel、DSI host 和 TCON 拓扑不同。可以移植的是“屏幕硬件合同”：
精确时序、mode flags、命令延时、电源/复位要求、I²C/背光连接关系；不能复制
Rockchip 的节点名、VP 路由和 Rockchip 私有属性。

## 3. Meizu E3 屏幕合同的精确差异

### 3.1 时序

社区 RK 成功值：

```text
pixel clock 157000000
1080 x 2160
hfp=115 hbp=13 hsync=3
vfp=10  vbp=10  vsync=2
```

A733 v001/v002 除 `vsync-len` 外均相同；当前使用 `vsync-len=4`。这不是最能
解释硬锁的单一变量，但它确实偏离了已验证的 Meizu E3 精确时序，后续候选
不应继续沿用 4。

### 3.2 DSI flags

按通用 bit 定义计算：

```text
社区 RK Meizu：VIDEO | BURST | NO_EOT | CLOCK_NON_CONTINUOUS | LPM = 0x0e03
Radxa RK 10FHD：VIDEO | BURST | EOT alias | LPM                  = 0x0a03
A733 v001：     VIDEO | BURST | NO_EOT | LPM                    = 0x0a03
A733 v002：     VIDEO | NO_EOT | LPM                            = 0x0a01
```

Radxa overlay 的 `MIPI_DSI_MODE_EOT_PACKET` 在 overlay 兼容头中实际 alias 到
`MIPI_DSI_MODE_NO_EOT_PACKET`，因此不能从名字推断它与 A733 的 bit 9 相反。

Allwinner BSP 明确定义并使用 bit 10 `MIPI_DSI_CLOCK_NON_CONTINUOUS`：
`dsi_open_hs_mode()` 会从持续 `HSTX` 路径改成 `HSTX_CLK_BREAK` 路径。因此，
社区成功方案中的这个 flag 在 A733 上不是“未知私有位”，是驱动真实支持的
模式。但它只在 PHY 配置和 DSI 基本寄存器配置之后影响输出启动，不能解释
v002 卡在 `sunxi_dsi_combophy_configure` 附近的首次启动停顿。

v002 已经实证 non-burst 路径不可用：它没有走完初始 combo-PHY/encoder enable；
所以不能因为官方 A7A 标准屏使用 non-burst，就继续把 non-burst 套到 Meizu E3。
社区 Meizu 和 Radxa 官方 RK 面板的共同点反而都是 burst。

### 3.3 DCS 退出延时

社区 RK：

```text
05 10 01 28   # display off，等待 16 ms
05 78 01 10   # sleep in，等待 120 ms
```

A733 v001/v002：

```text
05 00 01 28
05 00 01 10
```

当前 A733 在发出 sleep-in 后立即继续复位/断电流程，没有给屏控制器完成
sleep-in 的 120 ms。它不影响第一次上电，却会影响 LightDM -> Plasma 登录、
输出重配、DPMS 或 compositor 重新 modeset。既有 v001 正是在登录界面正常，
进入 Plasma 后开始 `sunxi_de_atomic_flush timeout`，所以这个差异与故障时机
直接相关，优先级高于随意增加通用 `power-delay-ms`。

### 3.4 复位电气方式

社区 RK：

```text
reset-gpios = <... GPIO_ACTIVE_LOW>;
pinctrl: GPIO, pull-none
```

没有 open-drain 标记，即推挽驱动。

当前 A733：

```text
reset-gpios = <&pio PD 19 (GPIO_ACTIVE_HIGH | GPIO_OPEN_DRAIN)>;
```

Allwinner `panel-dsi.c` 会把该逻辑线切换为 0、再切换为 1并停在 1。由于当前
描述为开漏，最终的“高”实际上是释放线路。

转接板 `.epro2` 内部网表显示，Radxa 侧 `LCD_RESET` 到手机屏侧 D2 pad 是直连
网络；该网络的 PAD_NET 端点只有连接器与屏幕端，没有发现离散上拉电阻。由此
推断当前 open-drain 释放后依赖 SoC 内部状态、寄生或漏电形成高电平，复位释放
的电平和上升沿不可靠。这与“每次冷启动概率性成功、成功时间不固定”高度一致。

注意：Rockchip 与 Allwinner panel 驱动对 active-low 的逻辑处理可能不同，后续
不能照抄 `GPIO_ACTIVE_LOW`；在 A733 驱动现有 0 -> 1 操作语义下，应保留能让
最终物理电平为高的 polarity，只去掉 open-drain，使其成为确定的推挽输出。

## 4. 背光与 I²C 的新结论

### 4.1 当前存在两套背光控制链

社区成功方案中：

```text
panel backlight -> sgm37604_bl
SGM37604 HWEN -> GPIO
亮度 -> I²C 12-bit register
```

当前 A733 中：

```text
panel backlight -> backlight0 (PWM，默认 73/255)
sgm37604_bl -> 独立 backlight device，面板没有引用
```

这会造成 DSI 面板 enable/disable 只操作 PWM，SGM37604 的上电、寄存器初始化
和亮度生命周期不受 panel 框架排序约束。它能解释：

- 有时 SGM 初始化失败但 DSI 仍继续；
- 有时屏幕有图像但背光不亮或很低；
- 重启不掉电时 SGM 保留部分寄存器状态；
- 桌面亮度调节可能改的是 PWM，而不是实际 12-bit SGM 亮度。

转接板工程中包含 SGM37604，手机屏侧直接出现 `LEDA/LEDK1/LEDK2` 网络；这
支持“SGM 是该屏实际背光控制器”，而不是额外 PWM backlight 的判断。

### 4.2 软件 I²C 偏离两个官方/成功基线

社区 RK 使用硬件 `i2c0`，Radxa 官方 A7A 10FHD 则使用硬件 `twi2`，并配置：

```text
clock-frequency = 400000
pinctrl default/sleep
twi_drv_used = 1
no_suspend = 1
twi-supply = ...
```

当前新建的 `i2c-gpio` 没有继承这些 vendor TWI 的电源、pin-state、no-suspend
和硬件控制器行为。转接板网表显示 SGM 的 `PANEL_SCL/SDA` 与触摸的
`TP_SCL/SDA` 通过两只三端 Q 器件构成双向电平转换，并在 panel 一侧上拉到
`IOVCC1V8`。这是标准开漏 I²C 电气结构，适合 SoC 硬件 TWI；没有证据要求用
软件 bit-bang。

因此，`SGM register did not latch`、SEC I²C `-EIO` 和概率性低背光最应该先
从硬件 `twi2`、供电和启动排序修正，而不是继续在驱动里增加重试。

### 4.3 当前驱动不是社区原版

SGM 当前 0.1.10 相对社区成功源有 121 行新增、62 行删除，主要变化包括：

- 强制 HWEN 低/高复位；
- 20 ms 启动等待；
- 写后读回校验，失败时 probe 返回 `-EIO`；
- 从 DT 读取默认亮度；
- 兼容不同内核 remove API。

这些改动改善了诊断，但也把社区原版“写失败仍继续注册”的宽松行为变成了
“任一寄存器不满足校验就完全不注册 backlight”。现有日志中的 probe `-5`
正是这一策略的结果。后续应先恢复官方硬件 I²C 和正确 backlight phandle，
再判断读回校验是否真的不兼容；不应先靠更多重试掩盖总线/供电问题。

SEC 驱动也做了 5.15 API、gpiod、I²C probe retry 和 remove 路径适配。它不能
原样回退到面向 RK 6.1 的文件，但应把改动限制在兼容性和已证实的启动延时，
避免让触摸驱动参与显示/背光控制。

## 5. 为什么 RK 能双屏，而 A733 会锁死

RK3576 基础 DTS 明确：

```text
HDMI -> VP0
DSI  -> VP1
VP0/VP1 各自有 primary plane 与 cursor plane
```

社区补丁还明确启用 `route_dsi` 并连接 `vp1_out_dsi`。这是 VOP2 的固定管线
划分。

A733 也有两个 CRTC，既有日志表明：

- DSI 初次使能使用 DE0/TCON0；
- HDMI 后续使能使用 DE1/TCON3。

所以不能简单说“两个屏被分到同一个 CRTC”。真正差别是 A733 的两个 CRTC
仍属于同一个 `sunxi-drm` / `display-engine-v352` 驱动和同一个 DE IOMMU
master。Plasma 登录时的跨输出 atomic commit 发生超时后，DE0 继续访问已经
解除映射的 framebuffer，随后出现：

```text
sunxi_de_atomic_flush timeout
DE0 invalid address 0xfa000000
IOMMU fault interrupt storm
RCU stall / system-wide lockup
```

因此：

1. 最初的 atomic timeout 可能由 Meizu DSI 精确模式、退出/重启顺序或 vblank
   丢失触发；
2. Allwinner DRM/IOMMU 驱动没有安全地从该 timeout 恢复，把一个显示故障放大
   成全系统锁死；
3. SGM/SEC I²C 失败能解释背光和触摸，但不能直接生成 DE0 framebuffer IOMMU
   fault；
4. RK 上成功说明屏、转接板和屏幕合同可用，不等于 Allwinner DE/DSI 驱动能
   无条件承受同样的双输出 atomic modeset。

## 6. 当前怀疑优先级

按不同症状分别排序：

### 概率性屏幕初始化

1. `LCD_RESET` 被错误配置成 open-drain，且转接板网表未显示外部上拉。
2. SGM/SEC 使用软件 `i2c-gpio`，偏离社区 RK 和官方 A7A 的硬件 I²C。
3. 面板未绑定 SGM backlight，驱动 probe 与 panel enable 没有依赖排序。
4. 冷启动、软重启和不断电重启造成 SGM/屏控制器残留状态不同。

### 亮度很低或不亮

1. PWM backlight 与 SGM backlight 两套独立控制链。
2. SGM I²C 寄存器写入/读回失败，0.1.10 会直接让 probe 失败。
3. SGM 在不断电重启后保留部分状态。

### 登录桌面后双屏异常或内核锁死

1. Meizu 的 exit sequence 缺少 16/120 ms，正好影响 greeter 到 Plasma 的
   输出重配。
2. v001 缺少 Meizu 成功方案的 `CLOCK_NON_CONTINUOUS`，且 vsync 仍为 4。
3. Allwinner DE atomic timeout + IOMMU fault recovery 缺陷是系统锁死的直接
   放大器。
4. v002 non-burst 已被实测否决，不能作为后续方向。

## 7. 后续候选的证据约束

下一版不能把 RK DTS 原样复制到 A733；应在 Radxa 官方 A7A 拓扑上翻译以下
已验证合同：

1. 保留官方 A7A DSI/virtual-panel/TCON graph，以及官方提交
   `4349013e...` 的 `port@1 reg=<1>`。
2. 恢复 burst；不再使用 v002 non-burst。
3. 使用 Meizu 精确 `vsync-len=2`。
4. 使用 Meizu 精确 exit 延时 16/120 ms。
5. 去掉 panel reset 的 `GPIO_OPEN_DRAIN`；不盲目照抄 Rockchip polarity。
6. 使用官方 A7A `&twi2`、pinctrl、supply、`twi_drv_used` 和 `no_suspend`，
   把 SGM37604 与 SEC 放在该硬件总线上。
7. 面板的 `backlight` 直接绑定 `sgm37604_bl`，移除 Meizu 不使用的 PWM
   backlight 控制链。
8. `CLOCK_NON_CONTINUOUS` 可作为驱动明确支持、社区成功方案明确要求的变量，
   但应在离线编译/回读后受控测试，并记录它只影响输出启动路径。
9. 不修改 DRM/DSI 内核驱动；如果精确屏幕合同仍触发相同 DE0 fault，则停止
   overlay 猜试，转为等待/验证 Radxa 官方 A733 内核更新。

为了区分辅助总线与 DSI/DRM，最安全的验证顺序是：

1. stock HDMI + 只启用硬件 TWI/SGM/SEC，验证多次冷启动的 I²C、背光和触摸；
2. 单 DSI 验证 reset、电源、精确 timing/flags 和 DPMS 重启；
3. 最后才启用 HDMI + DSI，并在进入 Plasma 前后采集完整串口和 DRM state。

每一步都应有独立的版本化 DTBO、SHA256、stock `l0r` 回退入口和
`rsetup/u-boot-update` 动态启用/禁用流程。

