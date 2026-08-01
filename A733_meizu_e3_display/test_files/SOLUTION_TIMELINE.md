# 测试与问题解决时间线

本文件给出跨 `mainline` 和 `codexline` 的全局阅读顺序。两个目录中的 `01`、`02` 都是各自路线的内部编号，不能直接拼成整个问题的解决顺序。

## 全局解决路径

```text
01 旧 5.15：只加入官方 graph 的 reg = <1>
        ↓  DSI 能显示，但 HDMI+DSI 登录仍硬锁
02 Codex：non-burst 假设
        ↓  未修复
03 Codex：RK 对比、push-pull、移除 I²C/触摸变量
        ↓  未修复，但捕获 stale framebuffer 关键日志
04 保存旧系统、Rescue、U-Boot 与日志，重刷 T4
        ↓
05 新 BSP 1.4.8 / Linux 6.6：重新只采用 reg = <1> 方向
        ↓  显示稳定，旧 IOMMU/RCU 链消失
06 分离新系统 GPU/EGL/KWin 拖影问题
        ↓
07 回旧 5.15：严格单 DSI 交叉验证
        ↓  正常
08 回旧 5.15：HDMI+DSI 交叉验证
        ↓  热插正常，冷启动登录硬锁
09 结合日志、FAE 和两版 BSP，定位旧混合 TCON DRM/DE 根因
```

## 目录映射

| 全局阶段 | 当前目录 | 测试作用 | 结果 |
|---:|---|---|---|
| 01 | `mainline/01_initial_overlay_validation` | 旧内核首次受控应用 `port@1 reg = <1>` | graph 正确，但没有修复旧双屏硬锁 |
| 02 | `codexline/01_nonburst_dsi_experiment` | 单变量移除 DSI burst | 否定 non-burst 是修复方向 |
| 03 | `codexline/02_rk_reference_pushpull_validation` | RK/A733 对比、push-pull、隔离 I²C/触摸 | 否定这些 DTS/电气假设；取得 old-FB unmap 后仍被 DE 扫描的关键日志 |
| 04 | `mainline/02_reflash_handoff` | 保存现场、Rescue、extlinux、DTBO 和重刷工具 | 建立可恢复的新系统验证入口 |
| 05 | `mainline/03_new_kernel_overlay_validation` | T4/6.6 上回归最初 `reg = <1>`，不带 Codex 后续修改 | DSI/HDMI 运行稳定，旧 fatal 链消失 |
| 06 | `mainline/04_new_kernel_graphics_diagnosis` | 分析 HDMI、DSI 同时出现的拖影 | 归为 GPU/EGL/KWin 相邻问题，不是旧 DRM 硬锁 |
| 07 | `mainline/05_old_kernel_single_dsi_crosscheck` | 相同 overlay、SGM only、物理断开 HDMI | 连续通过，证明单 DSI 不是充分故障条件 |
| 08 | `mainline/06_old_kernel_dual_display_crosscheck` | 相同旧内核和 overlay，对比热插与冷启动双屏 | 冷启动 SDDM→Plasma 复现 stale-FB/IOMMU/RCU 硬锁 |

## 按三个主要决策阶段理解

用户实际解决过程可以压缩为：

1. **旧内核 + `reg = <1>`：**面板适配方向正确，但系统问题仍存在。
2. **Codex 后续修改：**non-burst、push-pull、移除 I²C/触摸等均没有解决问题。
3. **新 BSP + 回归 `reg = <1>`：**系统稳定，说明真正修复变量是 BSP 1.4.8 的 DRM/DE 路径。

后面的旧内核单/双屏测试属于第四阶段——根因交叉验证。它们不是部署顺序倒退，而是用于证明：旧版的首要问题是 `TCON-LCD + TCON-TV` 登录重配置，而不是 panel、背光、触摸或 `reg = <1>`。

## 每个实验目录的阅读顺序

```text
docs/   先读：实验目的、固定变量、结论
src/    再看：实际 DTSO、DTBO、驱动和构建产物
log/    核对：串口、dmesg、DRM/IOMMU 原始证据
tools/  最后看：部署、采集和回滚方式
```

决定性根因说明最终汇总在 `../docs/FINAL_CONCLUSION.md`；安全启动和回滚方式见 `../docs/RESCUE_BOOT_AND_ROLLBACK.md`。
