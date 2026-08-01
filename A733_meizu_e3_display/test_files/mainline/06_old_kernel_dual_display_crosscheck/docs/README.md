# 5.15 老内核 DSI + HDMI 干净双屏测试

- 沿用 `l0` 测试系统：加载 `cubie-a7a-meizu-e3-display-v001-reg1-5.15.dtbo`。
- 沿用 `l0r` rescue：无 overlay，保留 `single`。
- 背光：SGM37604A only；触摸驱动不参与。
- 第一阶段保持 `hdmi-toggle-once.service` disabled，并屏蔽厂商的广义 DRM hotplug 规则。
- 目的：直接比较严格单 DSI 与原生 DSI+HDMI 双 CRTC 路径，避免厂商分辨率 toggle 成为混杂变量。
- 测试前单 DSI boot ID：`2a2e4660-b03a-4fa7-9673-0296ed6deaf5`，fatal count 0。

## 阶段 A：系统运行中接入 HDMI（通过）

- HDMI 接入后，KScreen 最初只启用了 HDMI；随后手动配置为扩展桌面：
  - DSI-1：`1080x2160+0+0`，DE-0 / tcon0。
  - HDMI-1：`1920x1080+1080+0`，DE-1 / tcon4，primary。
  - X framebuffer：`3000x2160`，两个 CRTC 共用 fb 169，paddr `0xf0000000`。
- 两路 CRTC 当时均为 `err=0`，没有 IOMMU、RCU、NULL、panic 或 atomic timeout。
- 用户确认两块屏幕视觉正常。
- 完整状态见 `../log/dual-hotplug-enabled.summary.txt` 与 `../log/dual-hotplug-enabled.dmesg`。

## 阶段 B：HDMI 保持连接后冷启动并登录桌面（失败）

测试时间：2026-08-01 02:04（Asia/Shanghai）。沿用相同 l0、相同 v001-reg1 overlay、SGM 背光驱动，厂商 HDMI workaround 仍被隔离。

用户观察：登录界面正常；手动登录进入 Plasma 后，DSI 与 HDMI 同时冻结，随后系统无法经 SSH 操作。

串口时间线：

- `9.767 s`：系统已到串口 login prompt；图形登录管理器 SDDM 已启动。
- `34.087194 s`：第一次 `L2 PageTable Invalid`，地址 `0xfa1f5000`，来源 DE0。
- `34.111 s` 起：DE0 以约 25 ms 周期持续访问未映射基址 `0xfa000000`。
- `55.187693 s`：CPU6 首次 `rcu_preempt self-detected stall`。
- `118.210362 s`：CPU6 第二次 RCU stall。
- 日志停止于 `121.611 s`，故障风暴仍未停止。

本次串口计数：

- `L2 PageTable Invalid`：1。
- `L1 PageTable Invalid`：3536。
- `Bug is in DE0 module`：3537。
- `Bug is in DE1 module`：0。
- RCU stall：2。
- NULL pointer / soft lockup：0。
- 本次启动未直接打印 `sunxi_de_atomic_flush timeout`，因此不能仅凭本日志断言 timeout 是第一触发事件。

## 本轮判定

1. v001-reg1 overlay 和 DSI 面板本身不是充分触发条件：严格单 DSI 多次登录及 full modeset 正常。
2. 双路硬件同时工作也不是立即触发条件：在已运行桌面中热接 HDMI 并启用双 CRTC 可以稳定、视觉正常。
3. 可重复的高风险窗口是“HDMI 启动时已连接，SDDM 登录界面切换到用户 Plasma 会话，双路显示状态重新分配/提交”。
4. DE0 在会话切换后继续扫描已经没有 IOMMU 映射的 `0xfa000000`。结合旧实验中同类故障的 framebuffer 历史记录（`map:0` 与 `unmap-ts`），最符合“旧 framebuffer 已解除映射，但 DE0/RCQ 仍持有或仍在使用旧地址”的生命周期/同步错误。
5. DE0 错误中断/异常风暴把 CPU6 拖入 RCU stall，因而即使 DE1 没有单独报告页表错误，HDMI 与整机也会一起冻结。
6. 厂商 `hdmi-toggle-once` service 和 udev 规则在本轮均已禁用，可排除其为这次冷启动卡死的直接原因。

完整串口：`../log/serial-COM4.log`

- 大小：920819 bytes
- SHA-256：`5509B5BE4B0CCB54DCB601B41266637F20A2ED05FEAF79D7562722582E5E8653`
- COM4 已停止采集并释放。

源码级根因、旧日志 framebuffer 生命周期证据及 v1.4.6/v1.4.8 对比见：

`../../../../docs/FINAL_CONCLUSION.md`
