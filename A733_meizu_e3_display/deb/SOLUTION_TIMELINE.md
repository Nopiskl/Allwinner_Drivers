# DEB 与最终解决方案时间线

本文件按“问题如何被解决”排列，而不是按目录字母、DEB 版本号或两条路线各自的内部编号排列。

## 先看最终结论

最终稳定方案不是 `0.1.10` non-burst 包，而是：

```text
BSP 1.4.8 / T4 / Linux 6.6
        +
最初的官方 graph 方向（port@1 / reg = <1>）
        +
适配 Linux 6.6 的 SGM37604A 背光与 SEC 触摸驱动
```

这套最终组合没有被重新打成一个经过实机验证的一体化 DEB。因此当前目录中“版本号最大的包”和“最终解决方案”不是同一个东西。

## 解决顺序

| 阶段 | DEB/源码 | 实际用途 | 结论 |
|---|---|---|---|
| 0：包基础 | `0.1.6` | 原始 DKMS 包 | 适配起点，不代表最终显示方案 |
| 0：驱动集成 | `0.1.7`、`0.1.8` | 迭代 SEC 触摸、SGM 背光、DKMS 与映射 | 为显示实验提供驱动基础 |
| 1：旧内核只改 graph | `0.1.9` | 在原 overlay 上加入官方 `port@1 reg = <1>` | DSI 能工作，但旧 5.15 的 HDMI+DSI 登录硬锁仍存在 |
| 2：Codex 实验 | `0.1.10` | 在 `0.1.9` 基础上移除 DSI burst | 没有修复 hard lock，已经否定，不是最终包 |
| 3：新内核回归最初方案 | 没有新的最终 DEB | T4/6.6 上重新使用 `reg = <1>`，不采用 non-burst/push-pull 等后续假设 | 显示稳定，证明关键变化来自新版 BSP DRM |
| 4：旧内核交叉验证 | 没有新 DEB | 回到旧 5.15，用相同 `reg = <1>` 分别测试单 DSI 和 HDMI+DSI | 最终限定为旧 BSP 的混合 TCON DRM/DE 问题 |

## 现有目录怎样对应这条线

```text
mainline/01_original_package                 0.1.6：包基础
mainline/02_driver_integration               0.1.7/0.1.8：驱动基础
mainline/03_official_graph_package           0.1.9：旧内核 reg=1 方案
codexline/01_nonburst_package                0.1.10：被否定的 non-burst 实验
../test_files/mainline/03_new_kernel_overlay_validation
                                               新内核重新采用 reg=1 的最终方向
```

`codexline/01_nonburst_package` 中的 `01` 只表示“Codexline 内第一个包”，既不是整个解决流程的第一步，也不是最终推荐顺序。

## 为什么后续日志会引用 `0.1.10` 的背光源码

旧内核单 DSI 交叉验证曾从 `0.1.10` staging 路径取出 `sgm37604a.c`。这只是复用已经验证的背光文件，不是安装或采用 `0.1.10` non-burst overlay。

以下三个版本中的背光源码完全相同：

```text
SHA-256 674F614B35827C95CCF8D87A858F4DC7D8B5E81E12F1F17335A9676840165941

0.1.8  drivers/backlight/sgm37604a.c
0.1.9  drivers/backlight/sgm37604a.c
0.1.10 drivers/backlight/sgm37604a.c
```

真正不同的是 overlay：

- `0.1.9`：官方 graph / `reg = <1>`，属于最终继续采用的方向。
- `0.1.10`：在此基础上改成 non-burst，实验失败，不能作为最终部署包。

## 使用指导

1. 研究旧包的演化时，按 `0.1.6 → 0.1.7/0.1.8 → 0.1.9 → 0.1.10` 阅读。
2. 判断最终技术方案时，按 `0.1.9 的 graph → 切换 BSP 1.4.8/6.6 → 6.6 驱动移植` 阅读。
3. 不要因为 `0.1.10` 版本号更大就安装它作为最终方案。
4. 不要虚构一个没有经过实机验证的“最终 DEB”；如果以后重新打包，应以 T4/6.6 实际文件为输入并重新完成安装、冷启动和回滚验证。
