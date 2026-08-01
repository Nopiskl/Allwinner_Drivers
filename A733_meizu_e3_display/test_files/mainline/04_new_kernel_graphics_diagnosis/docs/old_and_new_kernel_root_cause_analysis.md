# A733 r6/5.15 与 t4/6.6：DRM/GPU 根因复核

日期：2026-07-31

本轮只分析已有日志、运行时快照和 Radxa/Allwinner BSP Git 对象，没有修改开发板。

## 结论

旧 r6/5.15 的整机硬锁死，根因高度倾向于 sunxi DRM/DE 的 RCQ 提交、
page-flip 完成通知和 framebuffer/IOMMU 生命周期失配，而不是 PVR GPU 本身。

当前 t4/6.6 的 GPU/EGL/KWin 问题是另一条用户态图形栈问题。它能制造拖影、
黑窗、合成器关闭，也可能改变 atomic/page-flip 的压力，从而改变旧 DRM 缺陷的
触发概率；但它不能解释旧现场中“DE 继续读取一个已经 map:0 的物理地址”这一
直接证据。

对公开源码能给出的最窄修复边界是：

- `e1524a9d77fe5a2801ead100affea1686867d377`
- 提交标题：`aiot-linux-v1.4.8 release`
- 日期：2025-11-19
- 上一个公开基线：`b36af3872d4e6e91da6e929f4ccf4822b3ea9d66`
  (`aiot-linux-v1.4.6 release`)

v1.4.8 是直接建立在 v1.4.6 上的一次大提交；相关 DE/DRM/IOMMU 路径在这两点
之间没有更细的公开提交。因此不能诚实地再给出一个比 `e1524a9` 更细的公开
commit ID。

最强的具体候选改动是 v1.4.8 在 `sunxi_de_atomic_flush()` 中停用了：

```c
de_top_update_force_by_ahb(engine->top_hdl);
```

v1.4.8 保留了该行但将其注释。`top_hdl` 是整个 DE 的共享 TOP，而该函数是在每个
CRTC 的 RCQ flush 中调用；在 HDMI+DSI 两个 DE 输出交错提交时，强制 AHB 写共享
TOP 是最符合旧 RCQ timeout 现象的竞争/时序触发点。

同时，v1.4.8 还重写了 `de_top_set_rcq_update()` 的等待逻辑：旧版在 DE busy 位
尚未满足时，只要 current-line 大于 0 仍可直接写 RCQ update；新版不再用该
current-line 兜底路径。这也是直接作用于 A733 DE352 的次强候选。

## 版本和 GPU 对照

| 项目 | 旧 r6 | 当前 t4 |
|---|---|---|
| 内核 | `5.15.147-21-a733` | `6.6.98-3-aw2511` |
| BSP build ID | `18dcb68d3d` | `92c27523bf` |
| rootfs | Debian 11 | Debian 13 |
| KWin | 5.20.5 | 6.3.6 |
| Mesa EGL/GLX | 20.3.5 | 25.0.7 |
| Xorg | 1.20.11 | 21.1.16 |
| GPU 内核驱动日志 | `pvr 24.2.6603887` | `pvr 24.2.6603887` |
| GPU BVNC | `36.56.104.183` | `36.56.104.183` |

两个 build ID 均不能在公开的 `radxa/allwinner-bsp` Git 对象中解析，应视为
Radxa 构建树/下游树 ID，不能强行映射成公开 commit。版本归属只能用源码特征、
二进制反汇编和运行时 debug 输出交叉确认。

当前 t4 的 KWin 日志包含：

```text
Cannot find EGLConfig
Compositing disabled: no OpenGL support
Compositing is not possible
```

而且这些错误在刷机后的 stock HDMI-only boot 中就存在，早于 Meizu DSI overlay
和 SGM 背光驱动，说明当前 GPU/EGL 问题不是 DSI 引入的。

## 为什么旧故障属于 DRM/DE

旧现场已经记录到完整因果顺序：

```text
Plasma atomic modeset
  -> sunxi_de_atomic_flush timeout
  -> DRM 仍完成 page-flip/释放旧 framebuffer
  -> 旧 framebuffer 变成 map:0
  -> DE0 仍扫描旧物理地址
  -> IOMMU PageTable Invalid IRQ storm
  -> RCU stall / 网络失联 / 心跳熄灭
```

最有区分力的一次地址证据：

| 时间 | 事件 |
|---|---|
| 45.088696562 s | 旧帧 `0xfa000000` 被提交 |
| 45.192134770 s | 新帧 `0xfc000000` 为 `map:1` |
| 45.193001228 s | 旧帧 `0xfa000000` 变成 `map:0` |
| 45.301344 s | DE0 仍访问 `0xfa000000` 并触发 IOMMU fault |

另一次 r6 启动中有 116 次 atomic flush timeout、25679 次 PageTable Invalid，
随后出现 RCU stall。SGM、SEC 和软件 `i2c-gpio` 全部移除后仍可复现，排除了这些
外围驱动作为必要条件。

GPU 只负责产生像素或合成缓冲；DE 扫描哪个物理地址、何时认为 RCQ 已完成、
何时允许 DRM 释放旧 framebuffer，均由 DRM/DE/KMS 路径负责。GPU 即使提交了
异常内容，也不应使显示引擎在旧缓冲解除 IOMMU 映射后继续 DMA 读取它。

## v1.4.6 到 v1.4.8 的具体核对

A733 运行时设备树匹配：

```text
compatible = "allwinner,display-engine-v352"
```

因此 v1.4.8 中 `de350.rcq_skip_read` 和 `de210.rcq_wait_line` 的专用开关不作用于
A733，不能拿它们解释当前改善。

直接作用于 DE352 RCQ 提交的差异包括：

1. v1.4.6 每次 RCQ flush 调用 `de_top_update_force_by_ahb()`；v1.4.8 注释该调用。
2. v1.4.6 `de_top_set_rcq_update()` 有 `current-line > 0` 时强制写 update 的兜底；
   v1.4.8 删除该兜底，仅在 DE busy 条件合适时写 update。
3. v1.4.8 对 DE TOP、busy 查询、offline/writeback、CRTC vblank 处理做了较大整理；
   但当前运行时明确显示 `offline: disable`，所以当前稳定性不能归因于启用了
   offline composition。
4. IOMMU v1 驱动只从 1.5.1 增至 1.5.4，公开 diff 主要是 helper/接口和调试改动，
   没有发现能直接修复 framebuffer 提前解除映射的核心变化。旧 IOMMU storm 更像
   DRM/DE 失配的后果，而不是起点。
5. v1.4.8 的 `sunxi_de_atomic_flush()` 仍返回 `void`，50 ms 超时后仍只是打印；
   `sunxi_drm_crtc.c` 之后仍会调用 `sunxi_crtc_finish_page_flip()`。所以公开源码并未
   完整修好“超时如何向上层传播并阻止旧 FB 释放”。它更像消除了主要 timeout
   触发点，而不是建立了完整的失败恢复机制。

旧 `5.15.147-21-a733` 二进制反汇编中明确存在
`sunxi_de_atomic_flush -> de_top_update_force_by_ahb` 调用，并且旧 DRM debug state
没有 v1.4.8 新增的 `offline:` 字段。当前 t4 debug state 已有该字段，说明其显示
驱动代码至少属于 v1.4.8 这一代。

公开源码：

- https://github.com/radxa/allwinner-bsp/commit/e1524a9d77fe5a2801ead100affea1686867d377
- https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.6/drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c
- https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.8/drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c
- https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.8/drivers/drm/sunxi_device/hardware/lowlevel_de/de_top.c
- https://github.com/radxa/allwinner-bsp/blob/cubie-aiot-v1.4.8/drivers/drm/sunxi_drm_crtc.c

## GPU 如何影响屏幕

正常路径：

```text
应用
  -> GPU(OpenGL/Vulkan) 或 CPU 绘制客户缓冲
  -> KWin/Xorg 合成到 scanout framebuffer
  -> DRM atomic commit + GEM/IOMMU 映射 + fence/page-flip
  -> Allwinner DE 读取 framebuffer 并做 plane/blend
  -> TCON
  -> DSI 或 HDMI
```

GPU 并不直接发送 DSI/HDMI 信号。它影响的是交给 DRM 的像素内容、缓冲数量、
fence 完成时机和 page-flip 频率。

典型 GPU/用户态问题：

- 缓冲没有正确重绘或合成器关闭：拖影、旧窗口副本、黑窗；
- EGL/GLX/GBM 格式不兼容：KWin 禁用 compositing、Xorg 回退软件路径；
- GPU job/fence 卡住：应用或桌面卡顿，通常内核和 SSH 仍可响应；
- cache coherency/格式问题：两个输出读取同一 X framebuffer 时可同时看到错误内容。

典型 DRM/DE 问题：

- atomic/RCQ 提交超时；
- CRTC/plane 实际状态与 DRM 认为的状态不一致；
- framebuffer 在硬件停止扫描前被解除映射；
- DE 对无效物理地址发起 DMA，引发 IOMMU fault storm，最终拖垮整个内核。

## 当前置信度与保留项

- 旧硬锁死根因是 DRM/DE：约 85%。
- t4 的 v1.4.8 RCQ/DE TOP 改动消除了主要触发点：约 70%。
- 当前 KWin 未合成、负载较低，从而部分掩盖仍存的 DRM 边界缺陷：约 20%。
- PVR GPU 内核驱动自身直接制造旧 IOMMU/DE stale-address 链：低于 10%。

不能把当前一次长时间稳定直接写成“彻底修复”。更强验证应在将来 GPU/EGL 恢复
后，保持同一 t4 内核，重复冷启动、登录、双屏 atomic modeset、DPMS off/on 和
持续 page-flip；同时统计 atomic flush timeout、IOMMU fault、RCU stall。若这些
始终为 0，才能把“负载降低掩盖问题”的可能性进一步压低。

## 补充：为什么历史 DSI-only 也曾异常

双 CRTC 竞争不是旧缺陷的必要条件，只是重要放大器。更准确的必要条件是：旧
DE352 RCQ 路径在 atomic 切换中没有正确完成，而上层仍结束 page-flip、释放旧 FB。
单 DSI 同样使用 DE-0/RCQ，所以 DSI/TCON0/vblank/enable 时序一旦先触发 RCQ timeout，
也能进入同一 stale-FB 故障链。

同时，历史 `cubie-a7a-meizu-e3-dsi-only-debug.dtso` 并不是完整的单输出基线。它只做：

```dts
&hdmi0 { status = "disabled"; };
```

它没有同步禁用或重连 HDMI 关联的 TCON、DE graph、音频和 extcon。对应串口日志中
仍有 `sunxi_codec_hdmi` probe，并报告 HDMI extcon 获取失败；该次截取日志没有出现
`sunxi_de_atomic_flush timeout`、IOMMU PageTable Invalid 或 RCU stall，而系统服务已
继续启动。因此这次黑屏/无输出更适合归类为“不完整 component/graph 拓扑导致 DRM
没有正常形成输出”，不能当作一次已经严格证明的“纯单 DSI 同型硬锁死”。

所以当前结论分两层：

- 旧双屏硬锁死：已有完整 RCQ timeout→stale FB→IOMMU→RCU 证据；双 CRTC/共享
  DE TOP 是高概率放大因素。
- 历史 DSI-only 黑屏：测试拓扑不完整，现有日志不足以证明与双屏硬锁死完全同因；
  即使另一次纯 DSI 确实发生同型硬锁死，旧 RCQ 路径本身也允许单 CRTC 触发。

## 证据位置

- 总调查记录：`RADXA_A7A_MEIZU_E3_DISPLAY_INVESTIGATION.md`
- r6 刷机前快照：`test_files/mainline/02_reflash_handoff/log/snapshots/20260731-preflash-r6-v003-rescue/`
- 新内核 overlay 与驱动快照：`test_files/mainline/03_new_kernel_overlay_validation/`
- 新内核拖影诊断：`test_files/mainline/04_new_kernel_graphics_diagnosis/`
