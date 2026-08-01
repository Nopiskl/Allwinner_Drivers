# Radxa Cubie A7A 旧 5.15 双屏登录硬锁：实验与源码级根因分析

日期：2026-08-01

本文只做日志、实验结果和源码分析，没有继续修改开发板。当前开发板已在本轮故障中硬锁，后续操作仍应通过 `l0` 测试项和 `l0r` rescue 项进行。

## 原厂 FAE 最终口径（阅读本文前先看）

后续取得的原厂信息对早期判断作了关键修正，本文采用以下最终口径：

1. BSP 1.4.6 使用的也是旧 sunxi DRM，并不是只有 `disp2` 才经过测试；原厂当时主要在 Android/SurfaceFlinger/HWC 用户态验证，而不是 Debian+X11。
2. 1.4.6 DRM 的产品定位是试用版本。原厂确认双 MIPI、LVDS 等以 `TCON-LCD + TCON-LCD` 为主的组合正常，但 `TCON-LCD + TCON-TV` 配合存在问题。DSI 走 TCON-LCD，HDMI 走 TCON-TV，本机正好进入已知薄弱拓扑。
3. DE 有独立于各输出 TCON 的更新和完成时序，所以部分函数“默认 complete”是厂商硬件模型，不是单独的错误。旧版真正的问题是：RCQ/scanout 地址尚未可靠锁存时也可能被当作 complete，DRM 随后解除旧 framebuffer 的 IOMMU 映射，而 DE 仍在扫描旧地址。
4. FAE 所说的新驱动接入 extcon、每次 CRTC 变化都刷新，主要修正连接状态、mode/timing 与完成判断的一致性；它不是 framebuffer 锁存器，也不能单独解释修复。BSP 1.4.8 同时收紧了 DE352 的 DFS/RCQ-control 更新路径，停止不适用的 force-by-AHB 强写，并调整 RCQ update 条件。
5. Radxa 官方 DSI 屏和本机 Meizu E3 都表现为 1.4.6 出现同类问题、1.4.8 不再复现。这一跨面板证据说明根因属于旧 DRM/DE 混合 TCON 路径，而不是 Meizu 面板初始化、`reg = <1>`、背光、触摸或 GPU。

完整故障链可以压缩为：

```text
HDMI 开机存在，SDDM 登录后切换到 Plasma
  -> TCON-LCD + TCON-TV 两个独立完成域参与双 CRTC 重建
  -> 1.4.6 试用版 DRM/DE 未可靠确认某一路 RCQ/scanout 已切换
  -> DE 自有完成路径仍返回 complete
  -> atomic cleanup 解除旧 framebuffer 的 IOMMU 映射
  -> DE0 继续读取旧地址
  -> IOMMU PageTable Invalid 中断风暴
  -> RCU 饥饿，HDMI、DSI 和内核一起冻结
```

Android 同样走 DRM，因此“Android 没复现”不能证明旧 DRM 正确。首要原因是原厂主测的双 MIPI/LVDS 拓扑没有进入 `TCON-LCD + TCON-TV` 已知问题路径；其次，Android HWC 的 validate/present、BufferQueue/gralloc 引用和 acquire/release fence 通常使旧 buffer 保活更久、提交形态也比 SDDM 到 Plasma 的整套 root framebuffer 重建稳定。这个用户态差异只能作为降低触发率和严重度的次级掩蔽因素，不能替代旧 BSP 显示驱动根因。

## 一、结论先行

这次实验已经把问题从“DSI 面板、设备树或 GPU 可能有问题”收窄到了一个很具体的内核故障：

> 本机 `5.15.147-21-a733 #21` 所用的 sunxi DRM/DE 在 HDMI+DSI 登录切换期间，没有可靠地保证新的 RCQ/scanout 地址已经被显示硬件接受，就允许 DRM 释放旧 framebuffer。旧 framebuffer 的 IOMMU 映射随后被删除，但 DE0 仍继续扫描旧地址，于是产生连续的 `PageTable Invalid` 中断。中断风暴占用 CPU，RCU 无法调度，最后表现为 HDMI、DSI 和整个系统同时冻结。

这里的“旧地址仍被扫描”不是推测：旧故障日志中的驱动自带 framebuffer 跟踪记录显示，`0xf4000000` 对应的旧 framebuffer 已经被标为 `map:0` 并记录了 `unmap_ts`，之后 DE0 又访问了这个 framebuffer 范围内的 `0xf5697000`，继而反复访问基地址 `0xf4000000`。本次冷启动登录故障则以相同形式反复访问另一块旧地址 `0xfa000000`。

目前可作如下定性：

| 判断 | 置信度 | 说明 |
|---|---:|---|
| DE0 正在读取已经解除 IOMMU 映射的旧 scanout framebuffer | 100% | 驱动 map/unmap 追踪、故障地址范围和 IOMMU 日志直接互证 |
| 本机 #21 故障属于 sunxi DRM/DE 的 atomic、RCQ 完成判定与 framebuffer 生命周期同步 | 95% | 源码中存在明确的完成错误不上传、跳过 vblank 等待、立即清理旧 FB 的组合缺口；该判断不外推为所有 v1.4.6 产品均会失败 |
| 1.4.6 试用版 DRM 的 `TCON-LCD + TCON-TV` 混合提交是首要拓扑触发条件 | 很高 | 原厂明确说明双 MIPI、LVDS 路径正常而 LCD-TCON 与 TV-TCON 配合有问题；A733 DTS 和 TCON 驱动又证明 DSI/LVDS/RGB 与 HDMI 分属两套时序、IRQ 和扫描线判定路径；与单 DSI、单 HDMI、冷启动双屏和桌面后热插实验矩阵完全一致 |
| HDMI 开机存在、SDDM 切换到 Plasma 的双 CRTC 重配置是主要放大窗口 | 90% | 同一内核、DTBO 和背光下，单 DSI 与桌面后热插 HDMI 均通过，只有冷启动双屏登录稳定复现 |
| v1.4.8 阻止了 DE352 上不受支持的 DFS/共享 RCQ-control 强写 | 源码差异确定；故障因果高 | DE352 两版都未声明 `support_dfs`；1.4.6 却无条件 dirty DFS shadow，并在每个 CRTC flush 时把无 display 偏移的整块 RCQ control 强写到 disp0；1.4.8 先按能力返回且取消 force-by-AHB。Radxa 官方屏与本机屏均表现为 1.4.6 复现、1.4.8 消失，显著提高版本级因果置信度；具体由哪一项子改动解决仍需单变量 A/B |
| v1.4.8 删除 `current_line > 0` 的 RCQ control 整寄存器直写 | 中高 | A733/DE352 直接调用该函数；新版只在 DE busy 条件成立后做 read-modify-write，避免绕过条件并覆盖同寄存器其他位 |
| 静态 RTMX line-buffer 写法能解释两版稳定性差异 | 低 | 当前归档的 BSP 1.4.6 与 BSP 1.4.8 源码都采用 disp0=`0x2000`、disp1=`0x1000`；这是共有实现，不是判别变量 |
| PVR GPU 内核驱动是硬锁的主要根因 | 低于 10% | 故障 master 是 DE0，不是 GPU；新旧系统 PVR 版本一致；GPU 主要负责提高提交频率、暴露内核错误 |
| `reg = <1>`、面板初始化、背光或触摸导致本次硬锁 | 接近 0% | SDDM 和单 DSI 已正常显示；故障发生在图形会话切换后的 DE 内存访问阶段 |

因此，当前不能再把问题归因于“DSI 一启用就必然异常”，也不能简单称为 GPU 绘制错误。更精确的说法是：

> DSI 经 `TCON-LCD`、HDMI 经 `TCON-TV`。1.4.6 试用版 DRM 在二者参与同一次登录重配置时，未可靠协调两套独立的时序/完成域，显著扩大了 DE/RCQ 同步漏洞；真正令内核失效的是显示控制器读取已解除映射的 framebuffer。

## 二、本次实验为什么具有决定性

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

## 三、本次冷启动硬锁的直接证据

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

## 四、旧原始日志直接证明了“释放后仍扫描”

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

## 五、源码中的完整因果链

以下行号基于工作区 `radxa-allwinner-bsp` 的旧 v1.4.6 系源码。工作区 `radxa-kernel-a733` 的 worktree 内容曾被清理，但相应 Linux 5.15 DRM core 已通过 Git object 核对。

### 5.1 plane update 把 framebuffer DMA 地址写入 DE shadow/RCQ

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_device/hardware/lowlevel_de/ovl/de_ovl.c`

- 约 245～264、574～586 行：从 GEM framebuffer 得到 DMA/paddr。
- 约 273～303、588～603 行：把地址写到 overlay layer 的 `top_laddr*` 等 shadow 寄存器。
- `ovl_set_block_dirty()` 把相应寄存器块标为 dirty，等待 RCQ 提交到硬件。

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_crtc.c`

- `sunxi_plane_atomic_update()` 约 525～555 行调用 `sunxi_de_channel_update()`，并调用 framebuffer debug trace。

因此日志中的 `paddr` 就是准备交给显示引擎扫描的地址；它不是单纯的用户态渲染缓存记录。

### 5.2 v1.4.6 的 RCQ flush 有完成语义缺陷

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_device/hardware/lowlevel_de/sunxi_de.c`

`sunxi_de_atomic_begin()` 约 559～563 行基本为空，原本可能用于关闭/整理 RCQ update 的调用被注释：

```c
// de_top_set_rcq_update(engine->top_hdl, hwde->id, 0);
```

`sunxi_de_atomic_flush()` 约 689～785 行在 DE352/RCQ_MODE 路径中执行：

1. `check_update_finished(hwde)` 清理或读取前一状态；
2. v1.4.6 调用 `de_top_update_force_by_ahb(engine->top_hdl)`；
3. 调用 `de_top_set_rcq_update(..., hwde->id, 1)` 请求更新；
4. 以 2 ms 间隔、最多 50 ms 轮询 `check_update_finished()`；
5. 超时时只打印 `sunxi_de_atomic_flush timeout`；
6. 函数返回类型是 `void`，不能把失败传回 DRM atomic helper。

也就是说，即使它明确知道 50 ms 内没有完成，调用者仍会把这次提交当作正常完成。

本机旧 `5.15.147-21-a733 #21` 的二进制反汇编还直接确认：

- `sunxi_de_atomic_flush`：`ffff8000088e7894`
- `de_top_update_force_by_ahb`：`ffff8000088e94b0`
- `ffff8000088e7ab4` 存在到后者的 `bl`

所以“旧 #21 内核含 force-by-AHB 行为”不是仅依据仓库分支推断，而是已由实际运行内核二进制验证。

### 5.3 CRTC 无条件宣布 page flip 完成

同一文件 `sunxi_drm_crtc.c`：

- `sunxi_crtc_atomic_flush()` 约 1992～2040 行调用返回 `void` 的 `sunxi_de_atomic_flush()`。
- 调用返回后约 2035～2040 行无条件调用 `sunxi_crtc_finish_page_flip()`。
- 注释把这里描述成 “after rcq_finished”，但源码没有成功/失败返回值可供上层判断。

所以即使 RCQ 没有真正把新地址锁存到硬件，DRM event 也可能已经被宣布完成。

### 5.4 厂商 commit tail 明确跳过 vblank 等待并立即清理旧 framebuffer

这是本次源码复核中最关键的生命周期缺口。

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_drv.c`

自定义 atomic commit tail 约 181～204 行的顺序是：

```c
drm_atomic_helper_commit_modeset_disables(dev, old_state);
drm_atomic_helper_commit_modeset_enables(dev, old_state);
drm_atomic_helper_commit_planes(dev, old_state, ...);
drm_atomic_helper_fake_vblank(old_state);
drm_atomic_helper_commit_hw_done(old_state);
/* drm_atomic_helper_wait_for_vblanks(dev, old_state); */
drm_atomic_helper_cleanup_planes(dev, old_state);
```

Linux 5.15 DRM core 的标准 `drm_atomic_helper_commit_tail()` 则在清理 old state/old framebuffer 之前调用：

```c
drm_atomic_helper_wait_for_vblanks(dev, old_state);
```

DRM core 的注释也说明，等待 flip/vblank 的用途之一就是在释放旧 framebuffer 之前，保证硬件已经不再使用它。

旧 BSP 同时具备以下三个条件：

1. 下层 RCQ flush 失败不能返回错误；
2. CRTC 无条件发送 page-flip 完成；
3. commit tail 跳过 vblank 等待，立即 `cleanup_planes()`。

这会形成一个明确的安全漏洞：只要 RCQ 地址切换漏掉、延迟或完成位出现假阳性，上层就会过早放掉 old FB 引用。

需要注意：日志显示硬件在 unmap 后 160 ms 还在读取旧地址，远超正常的一帧等待，所以根本问题不只是“少等一个 vblank”；是 RCQ/DE 实际没有正确切到新地址。跳过等待和错误上传会让这个 RCQ 故障直接演变成 use-after-unmap，而不是被延迟或阻止。

### 5.5 旧 framebuffer 的映射确实会被删除

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_drv.c`

- `sunxi_drm_gem_fb_destroy()` 约 98～102 行先记录 unmap trace，再调用 `drm_gem_fb_destroy()`。

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_debug.c`

- 约 232～270 行记录 FB 指针、DMA 地址、尺寸、pitch 和 `mapped=1`。
- 约 273～303 行按 FB/地址匹配，并写入 `mapped=0` 和 `unmap_ts`。
- 约 99～126 行在 IOMMU 异常后打印该环形追踪。

因此旧日志中的 `map:0` 是内核驱动的对象生命周期记录，不是用户态猜测。

文件：

`bsp/radxa-allwinner-bsp/drivers/drm/sunxi_drm_gem.c`

- 约 64～98 行在 GEM 引用归零后解除 dma-buf attachment/mapping，或对本地 CMA 对象执行 `dma_free_wc()`，然后释放 GEM 对象。

文件：

`bsp/radxa-allwinner-bsp/drivers/iommu/sunxi-iommu-v2.c`

- 约 851～885 行的 unmap 删除页表映射，并使 TLB/PTW 失效。

所以一旦旧 FB 引用被 cleanup 路径释放，对应 IOVA 就不再合法；DE 继续读取时必然进入 PageTable Invalid。

### 5.6 为什么故障会变成中断风暴和 RCU stall

同一 IOMMU 文件约 1345～1418 行：

- 读取并打印 L1/L2 PageTable Invalid；
- 通过 `sunxi_iova_invalid_helper()` 找到 master 名称；
- 打印 `Bug is in DE0 module`；
- 清 TLB/PTW 和 fault status；
- IRQ handler 返回 `IRQ_HANDLED`。

处理函数只清除本次 fault，没有停止仍在使用旧地址的 DE。因此下一次扫描又 fault，再次进入 IRQ。约 40.42 次/秒的持续异常最终让 CPU6 上 RCU grace-period 线程长期得不到调度，出现 RCU stall；系统其他任务、SSH、桌面和两块屏幕于是一起失去响应。

这也解释了“串口每次最后一行不同”：真正的硬锁发生在异步显示提交和中断路径，普通启动日志只是当时最后来得及输出的内容。卡在 Wi-Fi、桌面、鼠标或某一行 systemd 日志，不代表该行对应模块是根因。

## 六、为什么只报 DE0，但 HDMI 和 DSI 都冻结

A733 的设备树并不是两个完全独立的显示引擎：

文件：

`bsp/radxa-allwinner-bsp/configs/linux-5.15/sun60iw2p1.dtsi`

- IOMMU masters 表中 DE 使用 id 8，名称为 `DE0`。
- display-engine-v352 节点使用 `iommus = <&mmu_aw 8 1>`。
- 同一个 DE 节点下面有 `port@0` 和 `port@1`，分别供应两条显示输出路径。

运行时路由为：

- DSI：DRM DE-0 → tcon0；
- HDMI：DRM DE-1 → TV-TCON（A733 DTS 标签为 `tcon3`）；`tcon4` 对应 eDP。

日志里的 IOMMU `DE0` 指的是物理 DE352/IOMMU master，而不是在说“只有 DRM CRTC 0 与故障相关、CRTC 1 完全独立”。两个 CRTC 共享同一个显示引擎、TOP/RCQ 资源和扩展桌面的 framebuffer 体系。一条 scanout 地址出错并形成 IOMMU IRQ 风暴后，整个 DE 和内核调度都受影响，所以两屏一起冻结是必然结果。

## 七、为什么双屏登录尤其容易触发

SDDM 登录界面正常说明：

- U-Boot、DT graph、panel probe 和背光已工作；
- DE 能建立一组初始双输出状态；
- 故障不是“开机完全无法初始化 DSI”。

登录 Plasma 时，KWin/KScreen/X 会更换桌面布局、root pixmap、scanout buffer 和 plane/CRTC 状态。这里不必假设 X server 被替换；即使同一个 X server，用户会话也会产生一轮密集的 framebuffer 分配、atomic commit 和旧 buffer 回收。双输出要求两个 CRTC 在共享 DE TOP/RCQ 上协调完成，使旧 BSP 的时序缺口更容易暴露。

而“先进入单 DSI 桌面，再热插 HDMI”没有经历完全相同的 SDDM → Plasma 双输出所有权和 framebuffer 交接顺序，因此能正常不矛盾。它证明双屏稳态可用，却不能证明所有双屏 atomic transition 都安全。

## 八、BSP 1.4.6 中与双输出高度相关的源码风险

### 8.1 共享 DE TOP block 的 RCQ header 归属不清

`sunxi_de.c` 的 `de_rtmx_init_rcq()` 会把同一个 `detop_hdl->block` 加入每个 display 的 RCQ block 列表。初始化 display 0、再初始化 display 1 时，每个底层 `reg_blk->rcq_hd` 都被重新赋值。因为 DE TOP 是单例，最后一次初始化可能覆盖共享 TOP block 的单个 `rcq_hd` 回指。

这意味着双 CRTC 同时使用共享 TOP 时，dirty 标记究竟属于哪一路 RCQ header 存在明确的设计歧义。更关键的是，这个 TOP block 的 `reg_addr` 在 `de_top_create()` 中只按
`de_reg_base + rcq_ctl_offset` 建立，没有加入 display 的 `0x40` 偏移；它实际指向 disp0
RCQ control。旧 BSP 又在**每个** CRTC flush 中调用 `de_top_update_force_by_ahb()`，所以
flush disp1 时也可能根据共享/后绑定的 dirty header，把整块 shadow 强写到 disp0 控制寄存器。

这与实验现象高度一致：单 DSI 只有一条 RCQ 控制流，顺序写后通常还能完成；双屏登录时
disp0/disp1 连续 flush，disp1 路径可能改写 disp0 的 RCQ control，导致 disp0 的新 OVL
地址没有锁存，而软件仍继续释放 old FB。它仍需寄存器追踪完成最后一步实证，但已经是
两个 BSP 源码差异中最具体的直接机制。

### 8.2 静态 RTMX line-buffer 是两版共有实现，不是版本差异

直接比较当前归档的 BSP 1.4.6 与 BSP 1.4.8 源码，二者的
`de_top_set_rtmx_enable()` 都采用静态 line-buffer 分配：disp0=`0x2000`、
disp1=`0x1000`，都没有在此函数内执行动态单/双屏分配和 not-busy 等待。

这段实现本身仍可能是共享 DE 的脆弱点，但由于两版相同，它不能解释“旧版高概率失败、
1.4.8 几乎不失败”。后续版本判断只以两个 BSP 最终源码树的行为差异为依据。

## 九、v1.4.8/T4 与本机 #21 的关键差异

以下只比较工作区归档的 BSP 1.4.6 与 BSP 1.4.8 最终源码。能确定的是两版功能实现
如何不同，以及这些差异与实测故障链是否吻合。

### 9.1 v1.4.8 不再在 DE352 上执行错误的 DFS/force-by-AHB 路径

两个 BSP 的 DE352 描述都没有设置 `.support_dfs = 1`，即该功能对 A733/DE352 不受支持。
但 BSP 1.4.6 的 `de_top_freq_div_apply()` 没有能力检查：

```c
reg->bits.m = m;
reg->bits.n = n;
de_top_set_block_dirty(priv, DE_RCQ_CTL_REG_BLK, 1);
```

而 `engine->de_devfreq_auto` 默认打开，所以每次 RCQ flush 都会走到这段代码。紧接着旧版调用：

```c
de_top_update_force_by_ahb(engine->top_hdl);
```

该函数不是按当前 `hwde->id` 更新，而是把共享 `reg_blks[0]` 的整个 32 位 shadow 写入
其固定 `reg_addr`；这个地址对应没有 display 偏移的 disp0 RCQ control。因此它不只写
m/n，还可能覆盖同一寄存器中的 `rcq_update` 等位。

BSP 1.4.8 的 `de_top_freq_div_apply()` 首先执行：

```c
if (!hdl->private->dsc->support_dfs)
        return 0;
```

所以在 DE352 上根本不会设置 `dfs_en`，也不会 dirty 共享 RCQ-control block。同时新版
`sunxi_de_atomic_flush()` 停用了：

```c
// de_top_update_force_by_ahb(engine->top_hdl);
```

两层保护叠加后，A733 的每路 flush 不再无条件改写共享/disp0 RCQ control。这是目前解释
1.4.8 几乎不再出现故障的首要 BSP 差异。

旧版双 CRTC 的危险顺序可以具体写成：

```text
flush(disp0): force(shared shadow -> disp0 RCQ_CTL)
              RMW disp0.RCQ_UPDATE = 1

flush(disp1): force(shared shadow -> disp0 RCQ_CTL)
              RMW disp1.RCQ_UPDATE = 1
```

第二次 force 仍写 disp0，而且 per-display RMW 并不会同步更新那份共享 shadow 中的
`rcq_update` 位，所以它可能把 disp0 刚发出的 update 恢复成 shadow 中的旧值。若硬件
已在两次写之间锁存 disp0 请求，则双屏正常；若尚未锁存，请求被覆盖，disp0 继续使用
旧 OVL 地址。这一“是否赶在第二次 force 前锁存”的窗口，能够同时解释旧版的概率性、
单 DSI 正常、冷启动双屏登录高概率失败和桌面后热插有时正常。

### 9.2 v1.4.8 重写了 `de_top_set_rcq_update()` 的触发逻辑

旧版本逻辑除 busy 判断外，还在 `current_line > 0` 时直接 `writel(1, reg_base)`，绕过
read-modify-write。新版本移除了这个 fallback，只在 `de_top_query_de_busy_state()` 满足
条件时请求更新，并始终保留寄存器中其他控制位。

A733/DE352 的 `rcq_wait_line` 在两个版本中都为默认 `false`，所以这项变化会直接作用于
本机任务上下文中的 `de_top_set_rcq_update()`。新版代码还支持在真正声明 DFS 能力的
SoC 上把 m/n 与 update 合并到同一次 RMW；但 DE352 因 `support_dfs=false` 不进入该
分支。对 A733 真正生效的是：不再写 DFS 位、取消跨 display 的 force-by-AHB，以及
RCQ update 不再采用 current-line fallback 整寄存器直写。

### 9.3 新版扫描线判断存在，但不是 A733 的直接稳定原因

v1.4.8 确实为 `RCQ_MODE && rcq_wait_line` 平台增加了“当前扫描线 +
`ver_front_porch`”判断，并在 CRTC atomic check 中缓存 `adjusted_mode`。这段逻辑用于
vblank IRQ 判断是否应完成 page flip，防止 IRQ 已延迟到下一帧 active region 时误发
上一帧 fence/event；它不是 `de_top_set_rcq_update()` 的触发条件。

但 A733 使用的 `de352_data` 在 BSP 1.4.6 与 1.4.8 中都没有设置
`rcq_wait_line=true`；设置该标志的是 DE210。因此 A733 会继续读取通用 DE busy 位，
不会进入上述 timing 分支。DSI 从 `.mode_set` 改用 `.atomic_mode_set`、使用本次 atomic
state 的 `adjusted_mode`，有助于模式状态一致性，但不能作为本机 1.4.8 稳定的主解释。

### 9.4 HDMI 路径还有次要稳健性改进

v1.4.8 还更新了 HDMI EDID 的读取、校验和释放方式，分开保存 boot state 与实际 HPD
enable 状态，并加强输出模式选择的错误处理。这些变化可以降低 EDID 生命周期错误、
启动时 HPD 状态不一致或异常 mode list 导致的额外 modeset。

但它们不是本次硬锁的首要解释：旧日志的直接故障 master 是 DE0，且真正闭合的因果链
是 old framebuffer unmap 后仍被 scanout。HDMI 改进主要减少触发次数；停止 DE352
不支持的 DFS/共享控制寄存器写入，以及收紧 RCQ update，才直接作用于 A733 硬件是否
正确锁存新地址。

### 9.5 v1.4.8 没有完全修复生命周期安全缺口

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

### 9.6 原厂测试范围与 Radxa 官方屏证据的最终修正

最新澄清后的正确事实是：原厂在 1.4.6 上使用的也是旧 DRM 驱动，但验证用户态主要是
Android/SurfaceFlinger/HWC；不能再写成“1.4.6 已在 Debian+X11 双输出中验证稳定”。原厂
进一步确认：1.4.6 的 DRM 属于试用版本，双 MIPI 与 LVDS 一类 `TCON-LCD` 路径没有问题，
但 `TCON-LCD + TCON-TV` 配合存在已知问题。1.4.8 才是转入稳定验证的新 DRM 路径，双
DSI、DSI+LVDS/RGB 以及包含 eDP 的产品组合在该版本验证稳定。Radxa 官方 DSI 屏在旧
1.4.6 DRM 上也遇到与本机同类问题，换到 1.4.8 后解决。

这组证据比之前的推断更有判别力：

- Meizu E3 与 Radxa 官方屏跨两个 panel 都能在旧版触发，排除本机面板初始化序列、
  `reg = <1>`、背光和触摸为通用主因；
- 同一类问题随 1.4.8 消失，强力支持问题位于 1.4.6 sunxi DRM/DE 共同路径；
- 单 DSI、单 HDMI、双 MIPI/DSI+LVDS 正常而 HDMI+DSI 异常，正好按同类 `TCON-LCD`
  与异类 `TCON-LCD + TCON-TV` 分界；这比笼统的“HDMI 动态性较强”更接近主触发条件；
- 1.4.6 Android 稳定只说明 Android 的提交形态和 buffer 生命周期较少把漏洞升级成致命
  fault，且原厂已经把 LCD-TCON/TV-TCON 配合列为试用版已知问题，不能证明旧 DRM 的
  完成语义对所有用户态都安全；
- 1.4.8 的稳定性不能笼统归因于 Linux 6.6 版本号，因为有直接可见的 BSP 显示驱动变化。

### 9.7 FAE 信息与源码如何闭合完整根因

#### 9.7.1 “DE 有自己的时序，部分函数必须默认 complete”的正确含义

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

#### 9.7.2 1.4.6 中能够制造“假完成/旧地址继续扫描”的具体路径

A733 使用 DE352/RCQ_MODE。两版 DE352 都没有声明 `support_dfs`，但 1.4.6：

1. `de_top_freq_div_apply()` 无条件修改 m/n，并 dirty RCQ-control shadow；
2. 每个 CRTC flush 都执行 `de_top_update_force_by_ahb()`；
3. 被强写 block 的 `reg_addr` 没有 `disp * 0x40` 偏移，固定落在 disp0 RCQ control；
4. `de_top_set_rcq_update()` 的旧 fallback 可整寄存器 `writel(1)`，循环耗尽也返回 0；
5. `check_update_finished()` 读取并清除 RCQ finish 状态；它能证明硬件报告某次 RCQ
   transaction finished，却不能证明本次预期的 OVL 地址 block 未被遗漏/覆盖且已成为
   实际 scanout；
6. flush 失败不能上传，old FB 又由 custom tail 迅速 cleanup。

双 CRTC 顺序执行时可能形成：

```text
disp0 plane 写入新地址并 set update
        ↓
disp1 flush 再用共享 shadow 强写 disp0 control
        ↓
disp0 请求可能已锁存，也可能被覆盖/漏发
        ↓
完成位看起来已经清零，软件按 DE 规则宣布 complete
        ↓
旧 FB destroy/unmap，但 disp0 仍扫描旧地址
```

这同时解释“有的故障先打印 atomic_flush timeout、有的完全没有 timeout”：显式 timeout
表示没有等到 finish；无 timeout 的故障则说明不能把 RCQ finish 状态等同于“预期的新
scanout 地址已经生效”，可能是错误/被覆盖的 shadow 内容完成了一次 RCQ transaction。

#### 9.7.3 extcon 与“每次 CRTC 变化都刷新”解决的是状态一致性

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

#### 9.7.4 `TCON-LCD + TCON-TV` 为什么是首要拓扑触发条件

A733 设备树和驱动把输出明确分成两类：

| 输出 | A733 TCON 类型 | 设备树路径 |
|---|---|---|
| DSI0/DSI1、LVDS0/1、RGB0/1 | `TCON-LCD` | `tcon0/1/2`，`compatible = "allwinner,tcon-lcd"` |
| HDMI0 | `TCON-TV` | `tcon3`，`compatible = "allwinner,tcon-tv"` |
| eDP0 | `TCON-TV` | `tcon4`，`compatible = "allwinner,tcon-tv"` |

源码位置为 `configs/linux-5.15/sun60iw2p1.dtsi:3838-4218`。其中 `tcon0` 的输出端点直接
列出 DSI0、DSI1、LVDS0 和 RGB0；`tcon3` 只连接 HDMI0，`tcon4` 连接 eDP0。这里也修正
一个容易混淆的表述：eDP 在 A733 上属于 `TCON-TV`，所以“DSI+eDP 稳定”只能作为
1.4.8 已修好混合 TCON 路径的证据，不能反推 1.4.6 的 LCD+TV 本来就稳定。

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
- 双 MIPI、DSI+LVDS/RGB 主要是 `TCON-LCD + TCON-LCD`，原厂确认正常；
- HDMI+DSI 是 `TCON-TV + TCON-LCD`，旧版在冷启动登录交接稳定触发；
- 桌面稳定后再热插 HDMI 能运行，说明混合 TCON 的稳态输出并非硬件上不可实现，缺陷在
  混合域的重配置/完成事务，而不是两种接口电气上不能并存。

因此因果层级应调整为：**混合 TCON 是首要拓扑触发器，旧 DE352 RCQ/DFS/force 行为是
制造错误锁存的底层机制，X11 立即销毁旧 FB 是把错误升级为 IOMMU 风暴的生命周期条件，
HDMI HPD/登录 modeset 是提高命中率的放大器。**

#### 9.7.5 为什么一个 X11 大桌面仍不是硬件同步事务

本机 3000×2160 root framebuffer 只统一了 X11 坐标空间。Linux 5.15 与 6.6 的
`drm_atomic_helper_commit_planes()` 在关键顺序上都是先更新 plane，再逐个 CRTC 调用
`atomic_flush()`。两个 CRTC 各有 mode、vblank 相位和 RCQ update，没有 group-latch。

SDDM 两屏正常表示初始 enable 最终成功；当时没有一个即将被销毁的旧桌面 FB。登录 Plasma
后的 root-FB/布局交接才同时具备“旧 FB 正在扫描、两个 CRTC 连续 flush、HDMI 可能改变
connector/mode、旧 FB 最后引用释放”。静态登录画面正常并不能证明下一次交接安全。

#### 9.7.6 为什么旧 Android 同样走 DRM，却没有暴露致命故障

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
- 原厂主要量产/验证的双 MIPI、LVDS 等同类 LCD-TCON 拓扑本就避开了已知的混合 TCON
  缺口；Android 产品路径又缺少本机 HDMI+SDDM→Plasma 的动态重建窗口。

X11/Plasma 本次则确实销毁了 3000×2160 old FB；驱动日志记录 `map:0/unmap_ts` 后，DE0
继续访问它。也就是说 Android 稳定主要是**没有把潜伏的地址漏切升级为 use-after-unmap**，
而不是 Android 绕过了 DRM 或证明旧驱动没有缺陷。即使 Android 的 fence 被错误地提前
signal，长期 gralloc buffer pool 仍可能让地址保持映射，只产生短暂旧帧而不触发 IOMMU。

这部分关于 Android 通用 fence/BufferQueue 语义由 AOSP 文档和 drm_hwcomposer 实现支持；
工作区没有原厂具体 HWC 源码，因此“其实际 HWC 是否逐帧等待哪个 out-fence”不能写成已
核实事实。但同类 TCON 拓扑、buffer pool 与无 SDDM 会话切换已经足以显著降低复现条件。

#### 9.7.7 1.4.8 为什么可以认为已经解决/避免本问题

1.4.8 同时收紧了两类条件：

- **DE/RCQ 层：**按 `support_dfs=false` 跳过不支持的 DFS，停用固定强写 disp0 control 的
  force-by-AHB，并重写 RCQ update；
- **状态层：**extcon/hotplug 完整接线、CRTC change 时刷新 adjusted timing、输出驱动使用
  atomic mode state，并改进 HDMI boot/HPD/EDID 状态管理。

原厂在 1.4.8 已稳定验证包含 `TCON-LCD + TCON-TV` 的产品组合；Radxa 官方屏与 Meizu E3
跨 panel 都从“1.4.6 同类故障”变为“1.4.8 稳定”，再加上本机
6.6/T4 长时间无 IOMMU/RCU 链，已经足以在工程上判断：**1.4.8 避免或解决了本次实际
触发路径。**仍需谨慎的是，1.4.8 的 `sunxi_de_atomic_flush()` 仍返回 `void`、custom tail
仍跳过标准 vblank wait，所以它更像把 DE 自有完成语义和状态刷新修到可用，而不是从形式
上加入了一层永不可能 use-after-unmap 的通用保护。

#### 9.7.8 整轮适配与故障的最终调用链

```text
Meizu E3 overlay/面板/背光成功初始化
        ↓
单 DSI、HDMI-only 均正常，证明物理链路不是充分故障条件
        ↓
旧 1.4.6 试用版 DRM 在 HDMI 开机存在时进入
TCON-LCD + TCON-TV 的双 CRTC 登录重配置
        ↓
X11 3000×2160 old FB 被新 root FB 替换
        ↓
两种 TCON 使用不同 vblank/扫描线/启动延迟，helper 又逐 CRTC flush
        ↓
旧版 DE352 DFS/共享 RCQ-control 强写、RCQ update/状态刷新竞态
        ↓
某一路新 scanout 地址没有可靠锁存，但 DE 自有完成路径仍默认 complete
        ↓
page-flip/commit 被宣布完成，custom tail cleanup old planes
        ↓
X11 释放 old FB，驱动记录 map:0/unmap_ts
        ↓
DE0 继续扫描 old IOVA（日志直接证明）
        ↓
IOMMU PageTable Invalid 中断风暴
        ↓
RCU stall，HDMI、DSI、SSH、心跳同时冻结
```

背光低亮/延迟点亮、触摸映射和新系统 GPU/KWin 拖影属于相邻但独立的问题；它们不能解释
DE0 对已解除映射 scanout 的 DMA 访问。随机停在不同日志/鼠标画面，也只是 IRQ/RCU
硬锁发生时各 CPU 和显示 scanout 所处位置不同。

## 十、GPU 在这里扮演什么角色

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

## 十一、对之前结论的更新

### 已被本次实验确认

1. `reg = <1>` 是遵循官方 A7A DSI graph 的必要修正，且它能正常驱动面板；它不是运行期硬锁根因。
2. 背光、触摸和面板初始化不是本次 hard lock 的根因。
3. 主根因属于旧 sunxi DRM/DE，而非 PVR GPU 内核驱动。
4. 两屏冻结是一个共享 DE/IOMMU/调度故障，不要求 DE1 自己也报告页表错误。
5. 每次卡死在不同屏幕页面或不同串口最后一行，是异步竞争和整机中断/RCU 失速的外部表现。

### 被本次实验收窄或修正

1. 不能再把历史上所谓“DSI-only 卡死”当成有效单 DSI 证据；当时有错误拓扑、残留 workaround 或其他 DTS 变量。本轮严格单 DSI 连续通过。
2. 双屏本身不是充分条件；桌面后热插双屏可稳定运行。
3. 最危险路径是 HDMI 开机存在时，从 SDDM 切到 Plasma 所引发的双 CRTC/FB 重配置。
4. `atomic_flush timeout` 不是必要前兆；最核心事实是旧 framebuffer 在 unmap 后仍被 DE 使用。
5. 首次主动 DSI off/on 的 `displl clk unable to lock` 是另一处时钟切换脆弱性，但它成功恢复且没有进入 stale-FB/IOMMU 链，不能解释本次登录硬锁。

## 十二、下一步应如何精确验证，而不是继续猜 DTS

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

## 十三、关键源码原文与日志逐段对照

本节保留构成结论所需的最小源码闭环。旧版代码来自工作区归档的 BSP 1.4.6
源码树；新版对照来自 BSP 1.4.8 源码树。行号以当前工作区文件为准。

### 13.1 framebuffer 地址进入硬件 shadow register

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

### 13.2 旧 RCQ flush：失败只打印，不能向上传递

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

### 13.3 旧 `de_top_set_rcq_update()` 也不能报告“根本没有发出 update”

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

### 13.4 CRTC 把 RCQ 返回等同于 page flip 完成

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

### 13.5 厂商 atomic commit tail 随后立即回收 old plane

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

### 13.6 framebuffer destroy 与日志 `map:0` 是同一条释放路径

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

### 13.7 IOMMU handler 为什么不能自愈

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

### 13.8 v1.4.8 的精确差异

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

### 13.9 RTMX line-buffer 对比

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

### 13.10 日志—函数—故障后果对照表

| 阶段 | 源码位置 | 原始日志证据 | 确定的含义 |
|---|---|---|---|
| 提交 scanout | `de_ovl.c`、`sunxi_drm_debug.c` | 旧日志 6065～6068 行记录 `f400 map:0`、`fc00 map:1` | 驱动已经提交新 FB，并记录旧 FB 状态 |
| old FB 被销毁 | `sunxi_drm_drv.c:98-102`、`sunxi_drm_debug.c:273-303` | `f400 unmap-ts:218562308519` | 软件生命周期已结束，映射进入释放路径 |
| DE 仍读 old FB | `sunxi_de.c`、`de_top.c`、OVL address register | 旧日志 432～438 行访问 `f5697000`，继而 `f4000000` | RCQ/硬件实际地址没有跟随软件状态完成切换 |
| 页表异常循环 | `sunxi-iommu-v2.c:1345-1418` | 本次日志 496 行起，3537 次 DE0 invalid-address | handler 清 fault 但 DE 继续重试 |
| 整机失去调度 | 同一 IRQ 循环持续占用 CPU6 | 本次日志 3908、14098 行 RCU stall | 两屏、SSH、心跳一起冻结是后果，不是多个独立故障 |

## 十四、最终回答

本次实验并没有推翻此前“旧 BSP DRM/DE 是主因”的判断，反而把它从概率性判断推进到了可复核的源码级因果链：

```text
HDMI 开机存在 + SDDM 登录 Plasma
        ↓
TCON-LCD + TCON-TV 两个独立时序域参与同一双 CRTC 状态重建
        ↓
1.4.6 试用版 DRM 逐 CRTC flush，旧 DE/RCQ 地址切换没有被可靠确认
        ↓
flush 失败无法上传，page flip 仍被宣布完成
        ↓
commit tail 跳过 vblank 等待，cleanup old planes
        ↓
旧 framebuffer 被 destroy / IOMMU unmap
        ↓
DE0 仍扫描旧 DMA 地址
        ↓
PageTable Invalid 约 40 次/秒
        ↓
CPU6 RCU stall，HDMI、DSI、SSH、心跳一起冻结
```

目前能够确切命名的是本机 #21 的故障类别和生命周期断点，不能把它泛化成“v1.4.6 多显示不可用”。原厂信息和 A733 源码共同把首要拓扑触发条件进一步限定为 1.4.6 试用版 DRM 的 `TCON-LCD + TCON-TV` 混合提交；双 MIPI、DSI+LVDS/RGB 的同类 LCD-TCON 组合不在这一范围。两个 BSP 源码树表明，1.4.8 几乎不再复现的最合理解释是：它尊重 DE352 的 `support_dfs=false`，不再 dirty 不适用的 DFS/RCQ-control shadow；同时停用会把整块 shadow 固定强写到 disp0 的 force-by-AHB，并删除旧版 `current_line > 0` 时的整寄存器直写 fallback。这些变化配合 CRTC timing refresh、atomic mode capture 与 extcon/hotplug 接线，收紧了两个 TCON 时序域在登录切换期间的 RCQ 控制状态。静态 RTMX 代码两版共有，timing-aware 分支又不适用于 DE352，二者都不是本机的首要版本差异。下一步若需要定位最小修复，可按 B1/B2/B3 拆分 A/B；产品方案则应直接使用 1.4.8 新 DRM，最后仍以 D 类完成语义和 old-FB 保活作为结构性防御目标。

原厂 1.4.6 验证使用的是旧 DRM + Android，而不是此前误记的 Debian+X11。Android HWC
通过 BufferQueue/gralloc 与 acquire/release/present fence 保留、循环使用显示 buffer，
原厂主要验证的双 MIPI、LVDS 等同类 LCD-TCON 产品又没有本机 SDDM→Plasma 的 root-FB
销毁窗口，因此旧 RCQ 漏切更可能只表现
为短暂旧帧，而不会立即解除当前 scanout 的 IOMMU 映射。Radxa 官方屏也在 1.4.6 遇到
同类问题并由 1.4.8 解决，说明这不是 Meizu panel 特有问题，而是旧 sunxi DRM/DE 路径。

一个 3000×2160 X framebuffer 也没有提供双 CRTC 硬件同步：5.15 和 6.6 的 DRM helper
都会逐个 CRTC 调用 `atomic_flush()`，两个输出分别在自己的 vblank/RCQ 边沿锁存。SDDM
两屏同时正常只证明初始状态成功，不证明登录后的下一次 FB 交接具备 group-latch。版本上，
现有证据支持“1.4.8 已在工程上解决/避免这条实际触发链”，其主要依据是 sunxi DE/RCQ、
CRTC timing refresh、atomic mode capture 与 extcon/hotplug 状态接线的组合变化，而不是
Linux 通用 DRM 的 5.15 与 6.6 版本号本身。FAE 所说“DE 自有时序、部分函数默认
complete”解释了厂商 completion 模型；旧版错误在于实际 RCQ/scanout 未交接时仍可能
进入 complete 且无 old-FB 保活兜底。
