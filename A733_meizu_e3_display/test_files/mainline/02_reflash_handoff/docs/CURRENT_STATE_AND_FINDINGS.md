# 刷机前最终状态与结论

## 1. 最后现场

最后只读快照采集于 2026-07-31 16:35–16:39（Asia/Shanghai）。

```text
主机名：radxa-cubie-a7a
系统：Debian GNU/Linux 11 (bullseye)
内核：5.15.147-21-a733 #21
root UUID：2a1371bc-7ff5-43a2-a3f9-7778b6d70186
当前 boot ID：d6ce9f34-06dd-4d67-927a-1b927270e582
当前启动：l0r，cmdline 包含 single
```

主要软件：

```text
linux-image-radxa-a733       5.15.147-21
u-boot-radxa-a733            2018.07-17
radxa-overlays-dkms          0.2.18
meizu-e3-dkms                0.1.10
Plasma Workspace             5.20.5
Mesa                         20.3.5
```

DKMS 在 5.15.147-21 上均为 installed：

```text
aic8800-usb
img-bxm-dkms
meizu-e3-dkms
radxa-overlays
```

## 2. 最终 extlinux 状态

`default l0`，菜单等待 10 秒。

- `l0`：加载
  `cubie-a7a-meizu-e3-display-v003-dsi-pushpull.dtbo`。
- `l0r`：不包含 `fdtoverlays`，并包含 `single`。

这意味着当前正常入口仍会复现 v003，而当前正在运行的救援入口没有应用
Meizu overlay。完整配置已经保存在快照的：

```text
boot/extlinux/
boot/extlinux-rendered.txt
```

`fw_printenv` 在旧系统中不存在；本项目实际使用的是 extlinux +
`u-boot-update`，不能依赖 `fw_setenv`。

## 3. 三轮主要 overlay 结果

### v001：官方 A733 graph 外壳 + Meizu 完整显示/背光/触摸

- 登录前/LightDM 可以正常。
- 进入 Plasma 后触发重复 `sunxi_de_atomic_flush timeout`。
- 随后 DE0 访问已解除 IOMMU 映射的旧 framebuffer。
- 产生 IOMMU IRQ storm、RCU stall、SSH/心跳失去调度。
- 典型旧 framebuffer 地址为 `0xfa000000`，另一次为 `0xf4000000`。

结论：不能只归因于面板没有初始化；故障发生在登录后的 atomic modeset。

### v002：只改变 DSI 为 non-burst

- 启动黑屏。
- DSI 初始化停在 combo-PHY/配置未完成路径。
- 没有复现 v001 的 DE/IOMMU 风暴。

结论：non-burst 不适合当前面板合同；“屏不亮”和“DE/IOMMU 硬锁”是两个
不同故障阶段。

### v003：DSI-only、无 I2C/SGM/SEC、reset 改为 push-pull

- 删除 `i2c-gpio`、SGM37604A 和 SEC 触摸节点。
- DSI 使用与 v001 相同的 burst/LPM/NO_EOT、1080×2160 时序。
- 登录前 HDMI 有输出，Meizu 无背光符合隔离条件。
- 进入桌面后仍复现相同的 DE0/IOMMU 故障。

上一故障启动的完整 persistent journal 新统计：

```text
sunxi_de_atomic_flush timeout = 116
PageTable Invalid             = 25679
Bug is in DE                  = 25668
is not mapped                 = 25677
RCU stall 相关行              = 21
```

首个关键时间：

```text
112.922995 s  第一个 sunxi_de_atomic_flush timeout
119.503159 s  L2 PageTable Invalid
119.513467 s  DE0 invalid address 0xfae77000
119.527320 s  L1 PageTable Invalid
119.537530 s  DE0 invalid address 0xfa000000
140.514976 s  第一条 rcu_preempt stall
```

故障一直持续到日志中的 908 秒附近，地址仍为 `0xfa000000`。

结论：I2C、SGM37604A、SEC 触摸 probe 和 reset open-drain 都不是整机硬锁的
直接充分原因。它们可能影响面板亮度和初始化成功率，但无法解释登录后的
DE/IOMMU 风暴。

## 4. 当前最有证据的故障链

```text
Plasma 登录/显示重新布局
  → 双输出 atomic commit / RCQ 更新
  → sunxi_de_atomic_flush 超时
  → 驱动仍将提交视为完成
  → 旧 framebuffer 被解除 IOMMU 映射
  → DE0 硬件仍扫描旧地址
  → IOMMU fault IRQ storm
  → RCU starvation / 系统近似硬锁
```

Meizu 的高带宽、时序、reset 或 panel contract 可能是触发条件；旧 Allwinner
DE/RCQ/IOMMU 错误恢复缺陷是把显示问题放大为整机卡死的机制。

## 5. BSP 对比结论

旧 #21 内核仍是 Allwinner BSP v1.4.6 风格：

- `sunxi_de_atomic_flush()` RCQ 超时只打印错误；
- 二进制中仍包含 `de_top_update_force_by_ahb()` 调用；
- 没有 v1.4.8 DRM state 的 `offline:` 字段。

已发现的官方 v1.4.8 release commit：

```text
e1524a9
https://github.com/radxa/allwinner-bsp/commit/e1524a9
```

这只是高价值 A/B 线索，不应在 t4 基线测试前直接修改 6.6 内核。

## 6. 新增 t4 测试要回答的问题

1. 6.6.98-3 是否仍出现 `sunxi_de_atomic_flush timeout`？
2. 是否仍出现 `Bug is in DE` 和未映射 framebuffer 地址？
3. 新版 U-Boot/ARISC/boot0 是否改变冷启动概率？
4. t4 自带 0.2.25 overlay 与当前官方主线 0.2.28 在 A7A Display 上有什么差异？
5. Plasma 6/X11 配置是否仍在登录时同时重新配置两个 CRTC？

t4 同时更换内核、U-Boot、Mesa 和 Plasma，因此“故障消失”只能证明新软件栈
整体规避或修复，不能仅凭一次成功断定是某一个组件。
