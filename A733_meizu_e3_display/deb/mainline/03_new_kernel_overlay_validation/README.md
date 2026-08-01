# Mainline 03：新内核 overlay 验证

本目录对应：

```text
test_files/mainline/03_new_kernel_overlay_validation/
```

最终稳定验证采用 BSP 1.4.8 / T4 / Linux 6.6、最初的官方 graph `port@1 / reg = <1>`，并单独移植适配 6.6 的 SGM37604A 背光和 SEC 触摸驱动。

该组合没有被重新生成并验证为一个最终一体化 DEB，因此这里不复制 `0.1.9` 或 `0.1.10`，也不虚构新的包产物。实际 6.6 驱动移植、overlay、工具和日志保存在对应的 `test_files` 实验目录。
