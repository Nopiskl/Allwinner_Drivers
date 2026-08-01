# Codexline：探索性验证

本路线保存 Codex 根据阶段性假设提出、但后来证明不是最终主修复方向的实验。

- `01_nonburst_dsi_experiment`：测试 DSI non-burst 假设，未修复 hard lock。
- `02_rk_reference_pushpull_validation`：合并 RK 社区适配对比、四平台对比，以及移除 I²C/触摸后验证 reset push-pull 的实验。该合并实验捕获了 old framebuffer 已 unmap 后仍被 DE 扫描的关键日志，因此其证据仍进入最终结论。

Codexline 用于保留推理过程和反证，不代表下一步应继续修改 DTS。
