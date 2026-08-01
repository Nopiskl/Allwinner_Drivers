# U-Boot、l0r 救援和动态回滚

## 1. 旧 R6 已验证的菜单行为

旧 R6 的 `/boot/extlinux/extlinux.conf`：

```text
default l0
prompt 1
timeout 10
```

- `l0` 是普通入口。
- `l0r` 是 rescue target，启动参数包含 `single`。
- 在旧 R6 菜单中发送数字 `2` 已成功选择 `l0r`。

这个数字只对旧 R6 的两个条目顺序有现场证据。刷入 t4 后应先从串口观察实际
菜单和标签，不要直接假设仍为 `2`。

## 2. 为什么默认会进入 l0

决定默认项的是 extlinux 中的：

```text
default l0
```

旧系统的 extlinux 是 `u-boot-update` 自动生成文件。正确修改源头是
`/etc/default/u-boot`、overlay 的 active/disabled 状态以及
`u-boot-update`，不要长期手工编辑生成文件。

## 3. 安全的 test/stock 结构

部署任何 Meizu 测试前必须满足：

```text
l0  = test，且只引用本轮一个版本化 Meizu DTBO
l0r = stock，无 fdtoverlays，包含 single
```

候选先安装为：

```text
/boot/dtbo/cubie-a7a-meizu-e3-display-vNNN.dtbo.disabled
```

启用前必须保存：

- DTBO SHA-256；
- 当前 extlinux；
- 当前活动 `.dtbo` 列表；
- 基准 DTB 与离线合并结果；
- 本轮 README 和串口日志路径。

确认 t4 仍采用相同机制后，使用：

```sh
sudo sh handoff/scripts/enable-versioned-overlay.sh \
  /boot/dtbo/cubie-a7a-meizu-e3-display-vNNN.dtbo.disabled
```

脚本会：

- 检查 `l0`/`l0r` 和 `single`；
- 备份 extlinux；
- 将指定文件从 disabled 改为 active；
- 运行 `u-boot-update`；
- 验证普通入口引用该 DTBO；
- 验证救援入口没有 `fdtoverlays`；
- 验证失败时自动恢复 disabled 状态。

## 4. 失败后的回滚

1. 物理重启。
2. 在 U-Boot 菜单选择标签带 `(rescue target)` 的入口。
3. 登录后先确认：

   ```sh
   grep -w single /proc/cmdline
   ```

4. 使用准确、完整的活动 DTBO 路径：

   ```sh
   sudo sh handoff/scripts/rollback-versioned-overlay-from-rescue.sh \
     /boot/dtbo/cubie-a7a-meizu-e3-display-vNNN.dtbo
   ```

该脚本只重命名为 `.disabled`，不会删除 DTBO；仅允许在包含 `single` 的启动中
执行，并在 `u-boot-update` 或验证失败时恢复原状态。

## 5. 串口

Windows 当前端口：

```text
USB-SERIAL CH340 (COM4)
115200 baud
8 data bits
no parity
1 stop bit
no flow control
DTR/RTS disabled
```

纯记录示例：

```powershell
.\handoff\scripts\serial-capture.ps1 `
  -PortName COM4 `
  -OutputPath .\log\runs\<run>\serial.log `
  -DurationSeconds 180
```

不要同时打开串口终端和采集脚本。涉及 U-Boot 选择时默认由现场人员手动操作，
不要后台自动发送菜单按键。

## 6. 离线拆盘操作的边界

离线操作前必须检查：

```sh
findmnt /media/nopiskl/rootfs
findmnt -no UUID /media/nopiskl/rootfs
lsblk -f
```

卸载必须成功后，才能对对应的整盘设备执行 power-off。不要把变量赋值文本误当
设备名，也不要执行重复 `mv`。之前文件系统只读 `e2fsck -fn` 显示正常，
不能把旧 NULL dereference 解释成 ext4 损坏；它发生在板端内核显示/内存路径。
