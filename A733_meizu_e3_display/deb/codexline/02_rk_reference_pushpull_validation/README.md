# Codexline 02：RK 参考与 push-pull 验证

本目录对应：

```text
test_files/codexline/02_rk_reference_pushpull_validation/
```

该阶段综合比较 Meizu E3 在 RK 平台、Radxa 屏幕在 RK/A733 平台的适配，并验证 push-pull 等假设。实验没有生成独立 DEB；对应 overlay、源码、工具和日志均保存在 `test_files` 中。

该路线没有解决旧 BSP 的 HDMI+DSI hard lock，不能当作最终部署包。它留下的重要证据是旧 framebuffer/DRM 状态与新显示事务不同步，而不是 push-pull 配置本身构成修复。
