# Mainline：正常验证流程

本路线保存以官方 Radxa A7A Display 拓扑为基础、能够进入最终结论证据链的正常流程：

```text
01_initial_overlay_validation
        ↓
02_reflash_handoff
        ↓
03_new_kernel_overlay_validation
        ↓
04_new_kernel_graphics_diagnosis
        ↓
05_old_kernel_single_dsi_crosscheck
        ↓
06_old_kernel_dual_display_crosscheck
```

其中新内核拖影属于用户态图形栈问题；旧内核单双屏对照用于定位 DRM/DE stale-framebuffer 硬锁。
