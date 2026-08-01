# 测试资料：两条验证路线

```text
test_files/
├── mainline/   官方结构和正常验证流程
└── codexline/  Codex 建议的探索性单变量实验
```

所有具体实验仍使用 `log/docs/tools/src` 分类。

## Mainline

| 目录 | 内容 |
|---|---|
| `mainline/01_initial_overlay_validation` | 重刷后基线、官方 graph 修正和首次 overlay 验证 |
| `mainline/02_reflash_handoff` | 刷机交接、救援、公共工具和无法单独归类的早期现场 |
| `mainline/03_new_kernel_overlay_validation` | 新内核上重新编译并验证最初 overlay |
| `mainline/04_new_kernel_graphics_diagnosis` | 新内核双屏拖影与 EGL/KWin/X11 分析 |
| `mainline/05_old_kernel_single_dsi_crosscheck` | 旧内核严格单 DSI 交叉验证 |
| `mainline/06_old_kernel_dual_display_crosscheck` | 旧内核热插双屏与冷启动登录硬锁对照 |

## Codexline

| 目录 | 内容 |
|---|---|
| `codexline/01_nonburst_dsi_experiment` | 移除 DSI burst 的探索性单变量测试 |
| `codexline/02_rk_reference_pushpull_validation` | 合并 RK 参考、四平台对比和 DSI reset push-pull 验证 |

`_shared` 和 `legacy-unclassified` 已移除；其中仍有价值的脚本、日志和规范已并入 `mainline/reflash_handoff`，旧 debug overlay 已并入 Codexline 的合并实验。
