# 测试时间线与结论演进

归档按两条路线保存：`test_files/mainline/` 是官方结构和正常验证流程，目录编号 `01`～`06` 表示主流程顺序；`test_files/codexline/` 是 Codex 建议的探索性单变量实验，编号 `01`～`02` 表示验证顺序。下文仍按实际发生时间叙述。

## 早期阶段：首次点亮、随机异常与救援

在结构化日志建立前，Meizu E3 屏幕经历了概率性初始化、背光很低、鼠标/触摸映射变化、HDMI/DSI 同时异常以及整机心跳停止。串口曾出现 RCU stall、NULL pointer 和 DE/IOMMU 错误。这个阶段证明故障不是单纯“背光没开”，但当时 DTS、HDMI workaround、触摸和双屏状态混杂，不能用于严格归因。

早期原始记录保存在：

`../test_files/mainline/02_reflash_handoff/log/legacy_unclassified/`

## 2026-07-31 05:46：Stock → v001-reg1

目录：`../test_files/mainline/01_initial_overlay_validation/`

- 旧 `5.15.147-21-a733 #21` stock HDMI-only 运行正常。
- 仅在最初 overlay 的 `dsi0 port@1` 增加官方 graph 所需 `reg = <1>`。
- LightDM 双屏登录界面正常，进入桌面后 HDMI 蓝屏、DSI 灰白。
- 串口记录 1402 轮 DE0 `0xfa000000` 页表错误，约 40.1 次/秒，并出现 RCU stall。
- 结论：graph/面板能初始化；故障发生在用户桌面引发的显示状态切换。

## 2026-07-31 14:29：v002 non-burst

目录：`../test_files/codexline/01_nonburst_dsi_experiment/`

- 单变量移除 `MIPI_DSI_MODE_VIDEO_BURST`。
- 离线编译、DT 合并、l0/l0r 和回滚均验证。
- 启动仍异常，进入 rescue 后回滚。
- 结论：burst/non-burst 不是旧内核 hard-lock 的根治变量；继续猜 DSI flags 不能解释 stale framebuffer。

## 2026-07-31 15:13：Meizu RK 参考分析

目录：`../test_files/codexline/02_rk_reference_pushpull_validation/docs/rk_reference_analysis.md`

- 对比 Meizu E3 在 RK3576 的社区适配、Radxa 官方 RK overlay 和 A733 BSP。
- 确认可借鉴的是面板时序、电气合同、reset/I²C/背光；不能直接复制 Rockchip VP/DSI 节点。
- 发现 A733 方案的 GPIO-I²C、背光绑定和 reset open-drain 与 RK 成功方案不同，但这些差异不能解释 DE 页表风暴。

## 2026-07-31 15:42：四象限显示分析

目录：`../test_files/codexline/02_rk_reference_pushpull_validation/docs/platform_comparison_analysis.md`

- 横向比较 Meizu/8HD 在 RK3576/A733 四种组合。
- 确认官方 8HD 的成功不能直接证明 157 MHz Meizu 面板应该采用同一 DSI flag。
- 将面板物理层问题与共享 sunxi DRM/DE 故障分离。

## 2026-07-31 15:53：v003 DSI push-pull、无 I²C

目录：`../test_files/codexline/02_rk_reference_pushpull_validation/`

- 删除 SEC/SGM/I²C 节点，只把 LCD reset 改成推挽。
- 故障仍发生，排除触摸、背光 I²C 和 reset open-drain 为整机硬锁主因。
- 最重要的新证据：驱动环形追踪记录旧 `0xf4000000` 已 `map:0`，DE 随后访问其范围内的 `0xf5697000`。
- 这是“old framebuffer unmap 后仍被 scanout”的直接证据。

## 2026-07-31 16:40：重刷前交接

目录：`../test_files/mainline/02_reflash_handoff/`

- 保存旧 R6 最后现场、DTB/DTBO、extlinux、U-Boot、DKMS、日志和救援脚本。
- 固化 `l0` 测试、`l0r` rescue、只通过 `u-boot-update` 管理 overlay 的流程。

## 2026-07-31 17:08：T4 / Linux 6.6 v001-reg1

目录：`../test_files/mainline/03_new_kernel_overlay_validation/`

- 新系统为 Debian 13、`6.6.98-3-aw2511 #3`。
- 从最初 `v001-reg1` 开始重新编译，不带入 non-burst、push-pull 等后续变量。
- 安装已经验证的背光/触摸移植后，DSI 与 HDMI 可长时间运行，没有旧 5.15 的 IOMMU/RCU 致命链。
- 结论：同一面板和基本 overlay 在新 BSP 表现稳定，进一步把旧故障指向内核 DRM/DE 差异。

## 2026-07-31 21:23：T4 双屏拖影

目录：`../test_files/mainline/04_new_kernel_graphics_diagnosis/`

- HDMI 和 DSI 同步出现清晰、离散的旧窗口副本。
- 两 CRTC 扫描同一个 3000×2160 X framebuffer。
- KWin 报 `Cannot find EGLConfig`，OpenGL compositing 被禁用；stock HDMI-only 基线已有相同错误。
- 结论：拖影属于 EGL/KWin/X11 合成与重绘问题，不是 DSI panel 或旧 5.15 hard-lock 链。

## 2026-08-01：旧 5.15 严格单 DSI 交叉验证

目录：`../test_files/mainline/05_old_kernel_single_dsi_crosscheck/`

- 恢复旧 `5.15.147-21-a733 #21`。
- 使用原始 `v001-reg1`；只安装 SGM 背光，不安装触摸。
- 物理断开 HDMI，并完全隔离厂商广义 DRM hotplug workaround。
- 连续三次启动、登录 Plasma 正常；两次 DSI full modeset 完成。
- 结论：DSI overlay/面板本身不是充分触发条件。首个 modeset 的 PLL lock 告警是独立脆弱点，没有进入 IOMMU/RCU 链。

## 2026-08-01：旧 5.15 双屏干净对照

目录：`../test_files/mainline/06_old_kernel_dual_display_crosscheck/`

- 单 DSI 桌面运行后热插 HDMI、建立扩展双屏：视觉正常，两路 `err=0`。
- HDMI 从开机连接：SDDM 正常；登录 Plasma 后两屏和内核硬锁。
- 第一次 fault 为 `0xfa1f5000`，随后 3536 次访问 `0xfa000000`；CPU6 两次 RCU stall。
- 结论：主要触发窗口是 SDDM → Plasma 的双 CRTC/framebuffer/RCQ 交接；双屏稳态本身不是充分条件。

## 当前结论演进

```text
早期：怀疑面板初始化/背光/触摸/DSI flags
→ v003：排除 I²C、触摸和 reset 为主根因，捕获 stale-FB 地址
→ T4：相同面板与 overlay 在新 BSP 稳定，拖影另属 GPU 用户态栈
→ 旧 5.15 单 DSI：排除 DSI 本身为充分触发条件
→ 旧 5.15 双屏对照：定位双屏登录 transition
→ 源码复核：确认 RCQ 完成语义、page flip、vblank wait 和 FB cleanup 的生命周期缺口
```

## 2026-08-01：加入原厂 v1.4.6/v1.4.8 双输出信息（后续已修正范围）

- 初始信息一度被理解为原厂双 DSI 或 DSI+LVDS/RGB/eDP 在 v1.4.6、v1.4.8 的 Debian/X11 路径均完成验证；后续 FAE 信息澄清：1.4.6 测试使用旧 DRM + Android，1.4.8 才是当前稳定的新 DRM 路径。
- 该证据反证“A733 多显示硬件不可用”和“所有 v1.4.6 多输出均失败”；后续原厂又明确指出 1.4.6 DRM 是试用版本，同类 TCON-LCD 组合可用，但 TCON-LCD 与 TCON-TV 配合存在已知问题。
- 本机 #21 的 stale-framebuffer/IOMMU 日志不是原厂测试的反例，而是对该已知混合 TCON 缺陷的具体 Debian/X11 复现和失效后果记录。
- 直接比较 BSP 1.4.6 与 BSP 1.4.8 最终源码，两版均采用相同的静态 RTMX line-buffer 实现；它不是稳定性差异项。后续判断只依据两个 BSP 源码树的实际行为差异。
- BSP 对比进一步收窄到 A733/DE352：两版 DE352 都声明 `support_dfs=false`；1.4.6 的 `de_top_freq_div_apply()` 却无条件 dirty DFS/RCQ-control shadow，并在每个 CRTC flush 用无 display 偏移的 `reg_blks[0].reg_addr` 强写 disp0 RCQ control。1.4.8 先按能力返回，同时停用 force-by-AHB。
- 旧版双 CRTC 顺序可能表现为“disp0 set update → disp1 flush 再用未同步 shadow 覆盖 disp0 control → disp1 set update”；disp0 请求是否已被硬件锁存决定本轮正常或 stale-FB，能够解释概率性。
- v1.4.8 还删除旧 `current_line > 0` 时整寄存器直写 RCQ control 的 fallback，改为确认 DE busy 后做 RMW；该差异会直接作用于 `rcq_wait_line=false` 的 DE352。
- 复核 SoC match data 后修正：A733/DE352 的 `rcq_wait_line` 在两版均为默认 false，置 true 的是 DE210；因此新版 adjusted timing/扫描线 page-flip 判断不属于本机主调用链，不能作为 A733 稳定主因。
- 新版还改进 DSI atomic mode capture 与 HDMI EDID/boot-HPD 状态管理；前者帮助模式状态一致，后者主要减少 HDMI 异常 modeset，均低于 RCQ/DFS 变化的因果优先级。
- IOMMU fault handler、GEM/debug、OVL 地址写入以及关键 old-FB cleanup 顺序在两版没有相应修复，因此新版不是“把 fault 隐藏掉”，而是更可能不再制造错误的 RCQ/scanout 状态。
- 结论更新为：1.4.8 主要通过停止 DE352 不支持的 DFS/共享 disp0 控制寄存器强写并收紧 RCQ update，使问题几乎不再出现；但 `atomic_flush` 仍为 `void`、RCQ 失败仍不能可靠上传、atomic tail 仍跳过 vblank wait，因此它尚不是形式完备的 stale-FB 生命周期修复。

## 2026-08-01：同类 TCON 与 HDMI+固定屏路径对比

- A733 DTS 明确把 DSI/LVDS/RGB 接到 `allwinner,tcon-lcd`，把 HDMI 接到 `allwinner,tcon-tv`；eDP 也属于另一条 `tcon-tv`，所以不能再把 eDP 与 LCD-TCON 混为一类。
- DSI/LVDS/RGB panel 的拓扑和 mode 通常固定，无 HDMI 的 HPD、EDID、颜色/格式协商和运行时 connector 状态变化；源码确认 BSP dual-channel DSI 只有 master 创建 DRM connector/encoder，是一个逻辑 connector/CRTC。
- HDMI 可在 `atomic_check()` 触发 `mode_changed`，并在 DE flush 后执行 HDMI `smooth_config()`；开机连接、SDDM→Plasma 会产生更密集且不对称的双 CRTC 重配置。
- 完整固定接口 modeset 会先 disable 相应 CRTC；本机更危险的是 HDMI 被强制 `mode_changed`、DSI 仍 active 但同时更换 root FB 的不对称 atomic 事务。
- 因此原厂 v1.4.6 双 MIPI、DSI+LVDS 等同类 LCD-TCON 输出可用，与本机旧 #21 HDMI+DSI 登录硬锁并不矛盾；后者正是原厂指出的 LCD-TCON+TV-TCON 已知问题。

## 2026-08-01：为什么双 MIPI/LVDS 测试不会暴露混合 TCON 缺陷

- 双 DSI 的 slave 在 `sunxi_drm_dsi_bind()` 直接返回，只有 master 创建 DRM connector/encoder；它是一个 CRTC 的双物理链路，不会触发跨 CRTC force 覆盖。
- DSI/LVDS/RGB connector 无 `.detect`，mode 来自 panel；内部 eDP detect 固定返回 connected。HDMI 则有 HPD/EDID、hotplug event，并可在 `atomic_check()` 主动设置 `mode_changed`。
- bug 的致命条件不只是 modeset，而是“LCD-TCON 与 TV-TCON 两个独立完成域参加同一 atomic 更新 + 一路 RCQ 请求被后续 force 覆盖 + old FB 最后引用立即释放”。
- 常规模式/老化测试若复用静态 dumb FB 或长期保留多缓冲池，即使偶尔漏一次 RCQ，也只会短暂显示旧帧；映射仍合法，下一次 flip 可自愈，不会产生 IOMMU fault。
- 本机 SDDM→Plasma 使用两个 CRTC 共用的 3000×2160 X framebuffer，并在会话交接中销毁旧 FB；日志的 `map:0/unmap_ts` 证明它命中了普通 modeset 测试通常不覆盖的 framebuffer-lifetime 条件。
- 原厂后来明确承认 LCD-TCON 与 TV-TCON 配合有问题，因此不能再描述成“原厂未发现”；正确说法是 1.4.6 试用版已经知道该拓扑受限，而双 MIPI/LVDS 的合格测试没有进入相同缺陷路径。

## 2026-08-01：FAE 信息与 Android DRM 路径后的最终修正

- 原厂 1.4.6 测试同样走旧 DRM，但用户态是 Android/SurfaceFlinger/HWC，不是 Debian+X11；此前“1.4.6 原厂 Debian+X11 双输出稳定”的前提撤销。
- Radxa 官方 DSI 屏在 1.4.6 也遇到同类问题，升级 1.4.8 解决；本机 Meizu E3 同样在 1.4.8 稳定。跨 panel、同版本边界的结果强力支持旧 sunxi DRM/DE 通用路径，而非面板 DTS/初始化。
- FAE 说明 DE 有自己的硬件时序，部分 DRM 完成函数按设计必须默认 complete。源码中的 DE RCQ polling、立即 `finish_page_flip`、fake-vblank 和跳过通用 vblank wait 与此设计一致；真正缺陷是旧版在新地址未可靠锁存时也可能 complete，且没有 old-FB 保活兜底。
- FAE 说明新版完整接入 extcon，并在 CRTC 变化时刷新。源码直接确认 1.4.8 在 `mode_changed/connectors_changed` 时把 `adjusted_mode` 刷新为 `scrtc->timings`，中断完成判断读取该 timing；DSI/LVDS/RGB 也改用 atomic mode state。extcon 本身只同步连接状态，不直接完成 framebuffer 锁存。
- 两版最终源码都有受 `CONFIG_EXTCON` 控制的 HDMI/eDP extcon 代码，因此“源码出现 extcon”不是唯一差异；实际 1.4.8 配置/DT/用户态接线和 CRTC timing refresh 共同构成 FAE 所述新路径。
- Android HWC 使用 BufferQueue/gralloc 的循环 buffer 和 acquire/release/present fence。旧地址即使多扫一帧，旧 gralloc buffer 往往仍保持引用/映射并在下一次 present 自愈；X11/Plasma 本次则销毁了整个 3000×2160 old FB，日志直接证明 unmap 后 DE0 仍访问它，所以升级为 IOMMU IRQ 风暴。
- 最终工程结论：1.4.8 已解决/避免本次实际触发链；首要源码机制是停止 DE352 不支持的 DFS/共享 disp0 force 强写并收紧 RCQ update，配合 extcon/hotplug、CRTC timing refresh 和 atomic mode capture。具体子改动贡献仍可用 B1/B2/B3 单变量实验区分，但不再怀疑 panel、背光、触摸或 GPU 为硬锁主因。

## 2026-08-01：原厂确认 1.4.6 试用 DRM 的混合 TCON 限制

- 原厂确认双 MIPI、LVDS 路径正常，但 `TCON-LCD + TCON-TV` 配合有问题；1.4.6 DRM 的产品定位是试用版本。
- A733 DTS 与 `sunxi_tcon.c` 复核：DSI/LVDS/RGB 使用 `TCON-LCD`，HDMI 使用 `TCON-TV`，eDP 也使用另一条 `TCON-TV`；两类 TCON 分别查询 vblank IRQ、current line、start delay、FIFO 和 vblank enable。
- 实验矩阵与此完全一致：单 DSI、单 HDMI 正常；双 MIPI/DSI+LVDS 属同类 TCON；HDMI+DSI 冷启动登录属于混合 TCON 且触发；桌面后热插可稳定说明故障在混合域重配置事务而非稳态硬件不可共存。
- 因果层级更新：混合 TCON 是首要拓扑触发器；旧 DE352 RCQ/DFS/force 路径是错误锁存机制；HDMI HPD 与登录 modeset 是放大器；X11 及时 unmap old FB 使其升级为 IOMMU/RCU 硬锁。
- eDP 属于 TCON-TV，因此 DSI+eDP 在 1.4.8 稳定反而是新版已经修复混合 TCON 路径的旁证，不能用于证明 1.4.6 混合路径稳定。
