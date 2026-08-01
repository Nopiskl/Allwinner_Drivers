# t4 v001：DSI 手机屏清晰多重拖影只读诊断

开始时间：2026-07-31 21:23（Asia/Shanghai）

## 现象

用户确认手机屏已经点亮并可长时间运行，暂未观察到整机卡死。现场照片显示，
移动 KDE“系统设置”窗口后，旧窗口以清晰、离散、等间距的完整副本残留在屏幕
上；它不同于普通 LCD 像素响应慢形成的模糊尾迹。

## 本轮边界

- 只读采集，不重启、不切换 overlay、不加载已隔离的 SEC 触摸。
- 不修改 DSI flags、timing、KWin、Xorg、背光或 I²C 配置。
- 对比 HDMI-only 初始系统基线、当前 HDMI+DSI 双输出，以及串口同时间内核日志。
- 优先判断拖影是否已经存在于 X11 软件截图/framebuffer，还是仅存在于 DSI
  物理扫描输出。

## 现场确认与结论

用户随后确认 HDMI 与 DSI 两块实体屏会同步出现相同拖影。这一现象直接排除
魅族 LCD 像素响应慢、DSI panel 单独残影、SGM 背光调制等仅影响手机屏的原因。

当前 boot ID 为 `b117f8c6-71c8-4416-8bfa-770f126123af`。SSH 读回确认：

- DSI-1 为 1080×2160@59.36，位于 `+0+0`；HDMI-1 为
  1920×1080@60，位于 `+1080+0`；X11 虚拟桌面为 3000×2160。
- 两个 CRTC 不是各有一个独立桌面缓冲；DE-0 和 DE-1 同时扫描 X 分配的同一个
  framebuffer 166（XR24、3000×2160、DMA `0xfc000000`）。DE-0 读取左侧
  1080×2160，DE-1 读取右上 1920×1080。
- 因而两个实体输出出现相同历史窗口副本，说明异常已经在共同的 X11/共享
  framebuffer/DE 输入侧形成，而不是在 DSI PHY、panel 或背光之后形成。
- `sgm37604a` 已加载并绑定 `0-0036`，亮度为 2000/4095；它只控制手机屏亮度，
  不可能让 HDMI 产生相同窗口副本。
- `sec_ts` 当前未绑定且被 blacklist；本次运行不存在约 945 IRQ/s 的 SEC 风暴，
  因而当前拖影不能归因于触摸 IRQ 饥饿。

## 图形栈直接证据

当前会话是 Plasma 6.3.6 / KWin X11。配置中 `useCompositing=true`，但运行时：

```text
glxinfo -B:
Error: couldn't find RGB GLX visual or fbconfig

kwin_x11:
Cannot find EGLConfig, returning null config
kwin_core: Compositing disabled: no OpenGL support
kwin_core: Compositing is not possible

KWin supportInformation:
Compositing is not active
```

Xorg 使用 stock `/etc/X11/xorg.conf.d/20-modesetting.conf`：card0 的 sunxi KMS、
`AccelMethod glamor` 和 DRI2。日志先报告在 PowerVR BXM-4-64 上启用 glamor，
随后又报告：

```text
glamor: Implementation returned 0x1908/0x1401 read format/type for depth 30,
expected 0x1908/0x8368. Falling back to software.
```

板端同时装有 IMG/PVR 内核与 Xorg 集成包、Debian Mesa/GLVND，并同时向动态链接器
提供 `/usr/local/lib/libEGL.so.1`（PVR 路径）和
`/lib/aarch64-linux-gnu/libEGL.so.1`（系统路径）；GLES 也有重复提供者，而 GLX
来自 Mesa/GLVND。尚未取得每个 `/usr/local/lib` 文件的包归属读回，因此不能仅凭
路径断言具体错误文件，但“PVR EGL/GLES + Mesa/GLVND GLX 的接口/配置不完整”是
当前最集中的用户态嫌疑。

没有 OpenGL 合成时，窗口拖动依赖 Xorg 对旧窗口区域的 expose/damage、背景重绘和
直接 scanout。清晰、离散的完整旧窗口副本符合该路径没有及时清除旧区域；它不像
LCD 响应慢形成的连续模糊尾迹。XWD 抓取没有得到永久保留的多副本，说明污染主要
发生于拖动/更新过程而非静止后永久写坏 framebuffer；自动移动并恢复窗口位置后也
没有出现新的 kernel fatal 事件。

## 与 HDMI-only stock 基线的对照

刷机后、部署任何 DTBO 之前保存的 stock 快照为：

```text
../../03_new_kernel_overlay_validation/log/stock-snapshot/
boot_id=0f2667c9-8449-4e65-81f5-a38debfb5801
U_BOOT_FDT_OVERLAYS=""
仅 HDMI-1，X framebuffer 163，1920x1080
```

该 HDMI-only Plasma 会话在启动约 60 秒时已经留下与当前完全相同的错误：18 次
`Cannot find EGLConfig`，以及一次 KWin `Compositing disabled: no OpenGL
support` / `Compositing is not possible`。stock Xorg 配置同样强制 modesetting +
glamor + DRI2。

因此可以确认：本次 v001 `reg=<1>` overlay、SGM 驱动和双屏布局不是
EGL/GLX/KWin 合成失败的来源；这个基础缺陷在官方 HDMI-only 系统中已经存在。
但用户当时没有做实体 HDMI 拖动测试，所以不能严谨地宣称“stock 单 HDMI 肉眼一定
出现过相同拖影”。当前最合理的分层判断是：

1. **基础根因候选（高置信度）**：官方镜像中的 PVR/Mesa/Xorg/KWin 图形栈没有
   提供可用的 EGLConfig/GLX visual，导致 KWin 合成关闭，进入容易暴露重绘问题的
   非合成路径。
2. **DSI 的作用（中等置信度）**：加入 DSI 把单 HDMI 的 1920×1080 framebuffer
   扩展为 3000×2160，并让两个 CRTC 读取同一缓冲的不同 source rectangle；它很
   可能放大或稳定触发原有的 damage/软件绘制/缓存同步问题，但不是 DSI 命令、
   lane、panel timing 或背光本身制造了拖影。
3. **仍需 A/B 才能区分的下层机制**：Xorg 非合成重绘逻辑本身，还是 CPU 软件绘制
   到 sunxi DRM dumb buffer 后的 cache-coherency/scanout 更新问题。当前没有
   underflow、FIFO error、page-flip/vblank timeout、DE/IOMMU fault 支持 DSI
   传输或 DE 带宽故障假说。

## 内核、串口与 DPMS

采集及自动重绘测试后，以下当前启动计数均为 0：

```text
sunxi_de_atomic_flush timeout
PageTable Invalid / is not mapped
Bug is in DE
RCU stall / soft lockup
NULL pointer / panic
underflow / FIFO error
vblank / page-flip timeout
```

COM4 能只读打开，但系统空闲时 10 秒采样为 0 字节，没有取得额外故障文本；有效
内核时间线来自同一启动的 persistent journal。13:33 两路显示被 Plasma 空闲策略
同时置为 DPMS Off，伴随两次 `displl clk unable to lock`，但没有进入旧 5.15 的
DE/IOMMU/RCU 故障链。13:42 执行一次不落盘的 `xset dpms force on` 后，DSI 与
HDMI 均回到 connected/enabled/DPMS On，DSI encoder 完整 enable、HDMI PHY
重新 lock。

`hdmi-toggle-once.service` 属于官方 `radxa-system-config-allwinner` 包，stock
镜像中已经存在；它只在启动后做一次 HDMI 分辨率切换并关闭 X screensaver 定时，
不能解释登录后拖动窗口时两个输出同步出现副本。

最后一次成功 SSH 读回为 21:42:31（本地时间），之后新建 SSH 会话一度只能建立
TCP、无法取得 SSH banner；COM4 同时没有新字符。MobaXterm 的既有 SSH TCP 会话
仍显示 established。未取得心跳灯/实体画面确认前，不能把这一连接现象记成内核
卡死，也没有继续对板端进行写操作。

## 下一步最小 A/B（尚未执行）

1. 用 `l0r` stock/无 overlay、仅 HDMI 登录同一个 Plasma X11，会话内反复拖动同一
   窗口并录像。若仍拖影，直接归为官方图形栈问题；若不拖影，说明双输出/大
   framebuffer 是必要触发条件。
2. 保持当前 DT 与驱动不变，只做图形会话变量：验证可用的 Wayland 或修复后的
   EGL/GLX 合成；不要先改 DSI timing。如果合成恢复且拖影消失，即完成上层定位。
3. 若合成恢复后仍拖影，再用 X/DRM buffer 读回与实体屏同步录像区分 X damage 和
   sunxi DRM cache-coherency；此时才考虑内核显示缓冲路径。

完整证据：`ssh-live-state.txt`、`ssh-x11-capture.txt`、
`ssh-final-readonly.txt`、`ssh-post-wake-state.txt`、`t4-root-*.xwd/.bmp`。
