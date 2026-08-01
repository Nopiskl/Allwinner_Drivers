# 关键产物与日志索引

## 主记录

```text
RADXA_A7A_MEIZU_E3_DISPLAY_INVESTIGATION.md
RADXA_A7A_WORKING_RULES.md
```

## v001

目录：

```text
test_files/mainline/01_initial_overlay_validation/
```

关键文件：

```text
cubie-a7a-meizu-e3-display-v001.dtso
cubie-a7a-meizu-e3-display-v001.dtbo
cubie-a7a-meizu-e3-display-v001.readback.dts
sun60i-a733-cubie-a7a-meizu-e3-v001.merged.dtb
sun60i-a733-cubie-a7a-meizu-e3-v001.merged.dts
baseline-extlinux.conf
failed-v001-journal-kernel.txt
postboot-v001-serial-live.txt
rollback-v001-from-l0r.txt
```

## v002

目录：

```text
test_files/codexline/01_nonburst_dsi_experiment/
```

关键文件：

```text
cubie-a7a-meizu-e3-display-v002.dtso
cubie-a7a-meizu-e3-display-v002.dtbo
sun60i-a733-cubie-a7a-v002-merged.dtb
sun60i-a733-cubie-a7a-v002-merged.dts
v001-to-v002-source.diff
v002-serial-live.log
recovery-l0r-serial.log
rollback-v002-over-serial.log
```

`capture-and-select-l0r.ps1` 保存了旧 R6 自动发送数字 2 的实验，但按当前工作
规范不应在后续测试中后台自动选择菜单。

## v003

目录：

```text
test_files/codexline/02_rk_reference_pushpull_validation/
```

关键文件：

```text
cubie-a7a-meizu-e3-display-v003-dsi-pushpull.dtso
cubie-a7a-meizu-e3-display-v003-dsi-pushpull.dtbo
cubie-a7a-meizu-e3-display-v003-dsi-pushpull.readback.dts
cubie-a7a-meizu-e3-display-v003-dsi-pushpull.merged.dtb
cubie-a7a-meizu-e3-display-v003-dsi-pushpull.merged.dts
extlinux-before.conf
extlinux-after-enable.conf
serial-v003-boot.log
README.md
```

## 刷机前最终快照

```text
test_files/mainline/02_reflash_handoff/log/snapshots/20260731-preflash-r6-v003-rescue/
```

其中上一启动的 122 MB 未压缩 journal 是 v003 persistent journal 的完整
故障风暴证据；压缩快照只有约 9.1 MB。

## 官方 A733 overlay

仓库：

```text
radxa-overlays-official/
```

重点：

```text
arch/arm64/boot/dts/allwinner/overlays/cubie-a7a-radxa-display-8hd.dtso
arch/arm64/boot/dts/allwinner/overlays/cubie-a7a-radxa-display-10fhd.dtso
```

本地 HEAD：

```text
c79b70822a314a7c828d361cbe976780af45c0a3
```

## RK3576 Meizu 参考

```text
radxa-meizu-e3/
test_files/codexline/02_rk_reference_pushpull_validation/docs/rk_reference_analysis.md
test_files/codexline/02_rk_reference_pushpull_validation/docs/platform_comparison_analysis.md
```

该目录不是 Git 仓库，必须随工作区备份，不能只记录一个远端 commit。

## 旧 BSP 参考

```text
radxa-allwinner-bsp/
branch: cubie-aiot-v1.4.6
HEAD: 2045a3ca2a01f088c0314dc924bda59d154e363e

radxa-allwinner-device-a733/
branch: device-a733-v1.4.6
HEAD: 79d54f44e14111db3845096cef0639a6c9222707
```

`radxa-kernel-a733` 是不完整/稀疏的分析 checkout，Git 状态显示大量 tracked
文件缺失，不能当作可重复编译的完整内核树。后续应按 t4 的 6.6 package source
重新取得干净源码。

## DKMS 历史包

```text
meizu-e3-dkms_0.1.6_all.deb
meizu-e3-dkms_0.1.7_all.deb
meizu-e3-dkms_0.1.8_all.deb
meizu-e3-dkms_0.1.9_all.deb
meizu-e3-dkms_0.1.10_all.deb
```

0.1.10 是旧 R6 最后安装版本。所有旧包都只能作为源代码和差异证据，不能直接
安装到 t4/6.6。
