# Radxa Cubie A7A + Meizu E3 重刷交接包

更新时间：2026-07-31 16:40（Asia/Shanghai）

这个目录保存了重刷 RSDK t4 前的最后现场、可复现文件、救援方法和新系统
验证顺序。后续重新连接板子时，先阅读本文件和根目录下：

- `RADXA_A7A_WORKING_RULES.md`
- `RADXA_A7A_MEIZU_E3_DISPLAY_INVESTIGATION.md`

## 当前已经完成

- 通过 COM4（CH340，115200-8-N-1）确认板子已进入 `l0r` 救援 shell。
- 通过 SSH 从 `192.168.0.103` 只读采集刷机前完整状态。
- 保存当前及上一启动 journal、dmesg、运行时 FDT/DTS、基准 DTB、全部 DTBO、
  extlinux/U-Boot 配置、软件包/DKMS、DRM/背光/触摸和存储状态。
- 下载后的压缩包通过板端和本机 SHA-256 交叉验证。
- 保存最后一次串口现场，确认当前启动参数包含 `single`。
- 提供新镜像基线采集、串口采集、受控启用 overlay 和救援回滚脚本。

## 最重要的文件

| 文件 | 用途 |
|---|---|
| `CURRENT_STATE_AND_FINDINGS.md` | 旧 R6 现场与已经证实的故障链 |
| `T4_REFLASH_AND_TEST_RUNBOOK.md` | t4 刷写后应严格执行的顺序 |
| `UBOOT_RESCUE_AND_ROLLBACK.md` | l0/l0r、串口和 overlay 回滚 |
| `ARTIFACT_INDEX.md` | v001/v002/v003、官方参考和日志索引 |
| `T4_IMAGE_METADATA.md` | t4 构建版本、下载文件和校验值 |
| `scripts/remote-collect-preflash.sh` | 板端完整状态采集器 |
| `scripts/collect-over-ssh.py` | 使用密码 SSH 下载采集包 |
| `scripts/serial-capture.ps1` | COM4 串口记录器 |
| `scripts/enable-versioned-overlay.sh` | 建立并验证 test/stock 双入口 |
| `scripts/rollback-versioned-overlay-from-rescue.sh` | 在 `single` 救援模式禁用指定 DTBO |

## 刷机前最后快照

压缩包：

```text
../log/snapshots/20260731-preflash-r6-v003-rescue/radxa-a733-preflash-current.tar.gz
```

SHA-256：

```text
866c70ab6c31ab2d965c6ba2a8c66d01fefd1584e5a387026a1bbff8f8989f26
```

板端生成大小：`9081589` 字节。

解包核验副本位于：

```text
../log/snapshots/20260731-preflash-r6-v003-rescue/extracted/
```

最后一次串口确认：

```text
../log/snapshots/20260731-preflash-r6-v003-rescue/serial-rescue-final.log
```

## 下一次连接的最短路径

1. 刷入 t4 KDE `output_512.img.xz`（SD/eMMC）并保持原厂配置。
2. 先接串口启动，不安装旧 `.deb`，不复制旧 `.dtbo`，不修改
   `extlinux.conf`。
3. 记录登录前状态，然后从 HDMI 登录桌面并记录登录后状态。
4. SSH 恢复后运行根目录的 `remote-new-image-baseline.sh`。
5. 检查新系统的 `rsetup`、`u-boot-update`、`/boot/dtbo` 和
   `/usr/lib/linux-image-*`，确认 t4 的实际机制。
6. 以 t4 自带的 A7A Display overlay 为结构基线，为 6.6.98 重新编译
   Meizu 候选；旧 DTBO 只能作差异参考。
7. 离线合并验证通过后，先以 `.dtbo.disabled` 安装，再建立可从 U-Boot
   回退的 test/stock 双入口。

不要从旧 R6 直接恢复以下文件：

- `/boot/extlinux/extlinux.conf`
- `/boot/dtbo/*.dtbo`
- `/usr/lib/linux-image-5.15.147-21-a733/`
- `meizu-e3-dkms_0.1.10_all.deb`

它们分别绑定旧 root UUID、旧 DT 符号/节点和 5.15 内核 ABI。
