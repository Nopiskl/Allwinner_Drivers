# RK 参考与 DSI push-pull 合并验证

该目录合并了三项连续、彼此依赖的分析与实验：

1. `rk_reference_analysis.md`：Meizu E3 在 RK3576 的社区适配、Radxa 官方 RK/A733 overlay 与当前方案对比。
2. `platform_comparison_analysis.md`：Meizu E3 与 Radxa Display 在 RK/A733 上的四平台对照。
3. `pushpull_validation.md`：依据前两项差异，删除触摸/背光 I²C 变量并把面板 reset 改成推挽后的实机验证。

## 合并后的结论

- Rockchip 的设备树节点和 VP 路由不能直接复制到 Allwinner，但面板时序、reset、电气和 I²C 合同可以作为参考。
- push-pull、移除 I²C/触摸并没有消除旧内核硬锁，因此这些不是主根因。
- 本实验的 `log/serial-v003-boot.log` 捕获了最关键的生命周期证据：旧 framebuffer `0xf4000000` 已经被记录为 `map:0`，随后 DE0 又访问其地址范围内的 `0xf5697000`。
- 所以该实验虽然属于 Codexline 的探索性 DTS 路线，却为最终 DRM/DE stale-framebuffer 结论提供了直接证据。

## 目录内容

- `docs/`：三份原始分析及本合并说明。
- `log/`：push-pull 实机串口、journal、配置和状态输出。
- `tools/`：串口采集脚本。
- `src/`：push-pull overlay、编译/合并产物，以及已废弃的 DSI-only debug overlay。
