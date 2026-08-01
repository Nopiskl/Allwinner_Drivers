# 5.15 双屏冷启动登录冻结事件

日期：2026-08-01（Asia/Shanghai）

## 测试控制变量

- 内核：5.15.147-21-a733。
- l0：`cubie-a7a-meizu-e3-display-v001-reg1-5.15.dtbo`。
- l0r：无 overlay、`single`，用于救援。
- 背光：SGM37604A only；无触摸驱动。
- HDMI 在启动前已经连接。
- `hdmi-toggle-once.service` disabled。
- `/etc/udev/rules.d/60-hdmi-hotplug.rules -> /dev/null`。

## 观察与内核证据

用户确认 SDDM 登录界面正常；手动登录后 DSI 与 HDMI 同时冻结。

```text
[   34.087194][    C6] L2 PageTable Invalid
[   34.091616][    C6] 0x0x00000000fa1f5000 is not mapped!
[   34.097461][    C6] Bug is in DE0 module, invalid address: 0xfa1f5000, data:0x0, id:0x4
[   34.111144][    C6] L1 PageTable Invalid
[   34.115535][    C6] 0x0x00000000fa000000 is not mapped!
[   34.121388][    C6] Bug is in DE0 module, invalid address: 0xfa000000, data:0x0, id:0x4
[   55.187693][    C6] rcu: INFO: rcu_preempt self-detected stall on CPU
[   55.194906][    C6] rcu: 6-....: (1 GPs behind) ...
[  118.210362][    C6] rcu: INFO: rcu_preempt self-detected stall on CPU
```

计数：L2=1，L1=3536，DE0 invalid=3537，DE1 invalid=0，RCU stall=2。

## 解释边界

- 本日志没有打印 `sunxi_de_atomic_flush timeout`，所以不能把 atomic timeout 作为本次已证实的首个事件。
- 已证实的是：登录后的显示状态交接完成得不正确，DE0 仍扫描未映射的 `0xfa000000`。
- 结合此前相同症状时驱动导出的 framebuffer 历史（相关地址出现 `map:0`、`unmap-ts`），最可能是旧 framebuffer 的 IOMMU 映射释放与 DE0/RCQ 实际切换不同步。
- 高频异常一直发生在 CPU6，约 21 秒后引发 RCU stall，解释了为何 DE1 没有自身页表错误但 HDMI 和整机仍一起冻结。

## 与成功路径的对照

- 单 DSI：多次启动、登录和 full modeset 均正常。
- 已进入 Plasma 后热接 HDMI：双屏扩展正常，两个 CRTC `err=0`。
- HDMI 启动前已连接，再从 SDDM 登录 Plasma：稳定命中本次故障窗口。

因此本轮把问题定位到老 5.15 sunxi DRM/DE/RCQ 的“双 CRTC + 图形会话切换 + framebuffer 生命周期/atomic 同步”组合路径，而不是面板初始化、背光驱动或厂商 HDMI workaround。

原始串口文件：`serial-COM4.log`

SHA-256：`5509B5BE4B0CCB54DCB601B41266637F20A2ED05FEAF79D7562722582E5E8653`
