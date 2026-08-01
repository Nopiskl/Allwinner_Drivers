# RSDK t4 镜像元数据

发布页：

```text
https://github.com/radxa-build/radxa-a733/releases/tag/rsdk-t4
```

发布信息：

```text
tag：rsdk-t4
release commit：7cde5dd
发布时间：2026-06-12 07:53 UTC
构建时间：2026-06-12 08:02:41 UTC
产品：radxa-a733
发行版：Debian Trixie
桌面：KDE
状态：Pre-release / internal development test build
```

相对于旧 R6：

| 组件 | R6 | t4 |
|---|---|---|
| Debian | Bullseye 11 | Trixie 13 |
| 内核 | 5.15.147-21 | 6.6.98-3-aw2511 |
| U-Boot | 2018.07-17 | 2026.04-2 |
| radxa-overlays-dkms | 0.2.18 | 0.2.25 |
| Plasma | 5.20.5 | 6.3.6 |
| Mesa | 20.3.5 | 25.0.7 |

t4 相对 t3：

```text
linux-aw2511：6.6.98-2 → 6.6.98-3
u-boot-dlan17：2026.04-1 → 2026.04-2
```

t4 changelog 没有明确声明修复 DSI、DE、RCQ 或 IOMMU。内核包说明包括
overlay 依赖修复和子模块更新；U-Boot 包含 A733 内存布局、ARISC、boot0、
EHCI/pinctrl 等更新。

## SD / eMMC 下载

桌面测试使用：

```text
https://github.com/radxa-build/radxa-a733/releases/download/rsdk-t4/radxa-a733_trixie_kde_t4.output_512.img.xz
```

SHA-512：

```text
efc750277504398e1293bfaca017eed8ca7fe61c93c7cc56a14d5080337a9d015c47d2c0e2e565cf0d6587ab014b85f9293a4cea71183f1898c80a95dd53eacf
```

只有实际使用 UFS 模块时才使用 `output_4096.img.xz`。

官方说明 `radxa-a733` 统一镜像适用于 Cubie A7A/A7Z/A7S。t4 是测试版，
适合本次 A/B 验证，不应当作已经通过稳定性认证的生产镜像。
