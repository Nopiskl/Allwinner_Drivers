# Radxa A7A：从拆盘修复到 `l0r` 动态救援与回滚

日期：2026-08-01

## 一、结论

`l0r` 不是后来额外安装的救援系统，也不是独立的 recovery 分区。它是 Radxa 镜像中
`u-boot-update` 原生生成的第二个 U-Boot/extlinux 启动入口：使用与普通入口 `l0` 相同的
内核、initrd、DTB 目录和 Debian rootfs，但附加 `single` 参数进入单用户救援模式；同时，
Radxa 当前生成逻辑只把活动 DTBO 写入普通入口，不写入 recovery 入口。

本项目后来建立的安全模式是：

```text
l0  = 正常/测试入口，只加载本轮一个版本化测试 overlay
l0r = stock 救援入口，不加载测试 overlay，保留 single
```

其中 `l0`、`l0r`、`single` 和 `u-boot-update` 是 Radxa/Debian 镜像原有机制；版本化
DTBO、启用前检查、备份、验证和自动回滚脚本是本项目后来补充的使用规范。

## 二、最初为什么采用物理挂载修复

早期 DSI overlay 出错后，板子可能黑屏、SSH 不可达或在桌面阶段硬锁。当时尚未识别并
验证板上已有的 `l0r`，只能：

1. 关闭开发板并把存储设备连接到 Ubuntu 虚拟机；
2. 将 `/dev/sdb3` 挂载到 `/media/nopiskl/rootfs`；
3. 在宿主机中移动 `/boot/dtbo/*.dtbo`；
4. 使用 `sed` 直接删除 `/boot/extlinux/extlinux.conf` 中的 `fdtoverlays`；
5. `sync`、卸载文件系统、断开磁盘，再装回开发板测试。

当时还执行过只读文件系统检查：

```sh
sudo e2fsck -fn /dev/sdb3
```

结果五个检查阶段全部通过，没有显示 ext4 损坏。后来取得的内核日志也证明，无法启动或
硬锁的主要问题位于显示 DRM/DE/IOMMU 路径，不能简单归因于这次文件系统操作。

### 这种方法为什么过于复杂

- 每次失败都需要物理拆装存储设备；远程测试无法独立完成。
- 必须先用 `findmnt`、`lsblk` 和 UUID 确认挂载的是正确 rootfs。
- 挂载点可能因 shell 当前目录或文件浏览器占用而出现 `target is busy`，导致无法卸载。
- 重复执行 `mv` 会遇到源文件已经不存在、目标文件已经存在等状态不确定问题。
- 曾出现把变量赋值文本混入 `udisksctl power-off` 参数的命令错误风险。
- `extlinux.conf` 文件本身明确写着“自动生成，请使用 `u-boot-update`”，直接 `sed` 修改
  只是临时修补，下一次生成配置时可能被覆盖。
- 离线修改无法在执行前验证下一次启动仍有一个不受测试 DTBO 影响的入口。

这段经历促使后续流程必须满足两个条件：测试配置可以动态启用，同时无论测试是否失败，
都应保留一个无需再次拆盘的 stock 回退入口。

## 三、如何发现 `l0r`

转折点是检查用户提供的原始 `/boot/extlinux/extlinux.conf`。文件中已经存在：

```text
default l0
menu title U-Boot menu
prompt 1
timeout 10

label l0
        menu label Debian GNU/Linux 11 (bullseye) 5.15.147-21-a733
        linux /boot/vmlinuz-5.15.147-21-a733
        initrd /boot/initrd.img-5.15.147-21-a733
        fdtdir /usr/lib/linux-image-5.15.147-21-a733/
        append root=UUID=... rw ...

label l0r
        menu label Debian GNU/Linux 11 (bullseye) 5.15.147-21-a733 (rescue target)
        linux /boot/vmlinuz-5.15.147-21-a733
        initrd /boot/initrd.img-5.15.147-21-a733
        fdtdir /usr/lib/linux-image-5.15.147-21-a733/
        append root=UUID=... rw ... single
```

对比可立即得到：

1. `default l0` 表明普通入口是默认项；
2. `l0r` 的菜单名称明确标注 `(rescue target)`；
3. 两项的 kernel、initrd、fdtdir 和 root UUID 相同，说明不是两套系统；
4. `l0r` 多出的 `single` 会让 Debian/systemd 进入单用户救援模式；
5. `prompt 1`、`timeout 10` 表明上电后可以通过串口在十秒菜单期内选择其他入口。

随后读取板上的 `u-boot-update` 源码，进一步确认这不是偶然的手工配置。其默认值包含：

```sh
U_BOOT_ALTERNATIVES="${U_BOOT_ALTERNATIVES:-default recovery}"
U_BOOT_DEFAULT="${U_BOOT_DEFAULT:-l0}"
```

生成普通入口时会写入：

```text
${_FDTOVERLAYS}
```

生成 recovery 入口时则没有这一行，并在参数末尾添加：

```text
single
```

因此发现过程不是“自行发明一个 rescue 配置”，而是先从 extlinux 的两个入口识别出
Radxa 已有功能，再通过 `u-boot-update` 源码和实际生成结果验证其行为。

## 四、这个 rescue 究竟是什么系统

在旧 R6 镜像上，`l0r` 仍然是同一个 Debian 11 Bullseye、同一个
`5.15.147-21-a733` 内核和同一个 rootfs。在 t4 镜像上也是同样设计，只是对应 Debian 13
和 6.6 内核。

它与独立 Android Recovery 或另一套最小 rootfs 不同：

- 软件包、用户文件、`/etc` 和 `/boot` 都来自当前安装系统；
- 启动参数中带 `rw`，所以在 rescue 内的修改会永久保存；
- `single` 主要阻止完整桌面和大量常规服务启动；
- 网络不一定启动，所以串口是可靠的进入与操作通道；
- 只有当 `l0r` 确认没有 `fdtoverlays` 时，它才真正避开测试设备树；
- 如果 kernel、initrd、基础 DTB、rootfs 或 U-Boot 本身损坏，`l0r` 也未必能启动。

因此更准确的名称是“同一 Debian 系统的 overlay-free 单用户救援启动项”。

## 五、第一次经过证据验证的实际应用

受控 v001 overlay 启动后，登录界面能够显示，但进入桌面后 DE0 开始持续访问无效 IOVA，
产生 IOMMU fault 风暴和 RCU stall。屏幕、SSH、心跳均失效，串口 Magic SysRq 也没有被
及时处理。

当时执行的救援过程为：

```text
物理复位/重新上电
        ↓
在旧 R6 U-Boot 菜单选择第 2 项 l0r
        ↓
通过串口登录
        ↓
检查 /proc/cmdline 中包含 single
        ↓
确认 l0r 段没有 fdtoverlays，Meizu 模块未加载
        ↓
把活动 v001.dtbo 重命名为 v001.dtbo.disabled
        ↓
运行 u-boot-update 重新生成 extlinux.conf
        ↓
验证 l0/l0r 都不再引用失败的 overlay
        ↓
sync 后重新上电，恢复 stock 启动
```

现场 `/proc/cmdline` 确实包含：

```text
... rw ... single
```

当时活动 DTBO 文件仍存在于 `/boot/dtbo`，但 `l0r` 的 extlinux 段没有
`fdtoverlays`，所以该文件没有在本次启动时合并进运行设备树。这一区别很重要：
“磁盘上存在 `.dtbo`”不等于“当前 rescue 启动已经应用 `.dtbo`”。

旧 R6 现场已经验证菜单数字 `2` 对应 `l0r`；该数字依赖当时的条目顺序。更换镜像后必须
重新观察菜单标签，不能永久假定所有版本都按 `2` 选择 rescue。

## 六、最终固化的安全测试流程

### 6.1 启用测试前

1. 将候选文件安装为有版本号的禁用状态：

   ```text
   /boot/dtbo/cubie-a7a-meizu-e3-display-vNNN.dtbo.disabled
   ```

2. 保存 DTBO SHA-256、当前 extlinux 和活动 overlay 列表。
3. 确认 extlinux 同时有 `l0`、`l0r`，且 `l0r` 参数包含 `single`。
4. 启用候选时仅将准确文件名从 `.disabled` 改为 `.dtbo`，再运行：

   ```sh
   sudo /usr/sbin/u-boot-update
   ```

5. 验证 `l0` 只引用本轮测试 DTBO，而 `l0r` 完全没有 `fdtoverlays`。

### 6.2 测试启动失败后

1. 物理复位，在串口 U-Boot 菜单选择 `(rescue target)`。
2. 进入系统后首先确认：

   ```sh
   grep -w single /proc/cmdline
   ```

3. 备份当前配置：

   ```sh
   sudo mkdir -p /boot/extlinux/backups
   sudo cp -a /boot/extlinux/extlinux.conf \
     /boot/extlinux/backups/extlinux.conf.pre-rollback-$(date +%Y%m%d-%H%M%S)
   ```

4. 只重命名准确的失败候选，不删除文件：

   ```sh
   sudo mv /boot/dtbo/cubie-a7a-meizu-e3-display-vNNN.dtbo \
     /boot/dtbo/cubie-a7a-meizu-e3-display-vNNN.dtbo.disabled
   ```

5. 通过官方生成器更新配置：

   ```sh
   sudo /usr/sbin/u-boot-update
   ```

6. 检查结果：

   ```sh
   grep -nE '^(default|label|[[:space:]]*fdtoverlays|[[:space:]]*append)' \
     /boot/extlinux/extlinux.conf
   ```

7. 确认失败 DTBO 不再被引用、`l0r` 不含 `fdtoverlays` 后执行 `sync`，再重启或物理
   重新上电。

工作区脚本
`test_files/mainline/02_reflash_handoff/tools/scripts/rollback-versioned-overlay-from-rescue.sh`
已经把上述操作固化，并额外执行以下保护：

- 如果 `/proc/cmdline` 不含 `single`，脚本就拒绝回滚；
- 只接受 `/boot/dtbo/*.dtbo` 范围内的准确路径；
- 修改前备份 extlinux；
- `u-boot-update` 失败时恢复原活动状态；
- 如果生成后的 `l0r` 含 `fdtoverlays`，立即恢复原状态并报错；
- 最后执行 `sync` 并输出禁用文件的 SHA-256。

## 七、必须保留的边界

1. 不要长期手工编辑自动生成的 `extlinux.conf`，应改变 overlay 的 active/disabled
   状态后运行 `u-boot-update`。
2. 不要把 `.dtbo` 文件是否存在当作当前设备树是否加载的证据，应检查本次 U-Boot 入口
   及运行时设备树。
3. `single` 与“不加载 overlay”是两件事；两项都验证通过才可称为安全救援入口。
4. 普通系统已经进入 IOMMU/RCU 中断风暴时，不应继续通过 SSH修改启动文件；应物理复位
   进入 `l0r`。
5. 每个新镜像都要重新核对 extlinux 菜单、默认项和 recovery 生成规则。
6. 如果 `l0r` 也无法到达 shell，再退回拆盘挂载、U-Boot 命令行或重刷镜像；离线修复是
   最后兜底，不再作为每轮 DTSO 测试的常规流程。

## 八、证据文件

- 原始/最终 extlinux 现场：
  `test_files/mainline/02_reflash_handoff/log/snapshots/20260731-preflash-r6-v003-rescue/extracted/radxa-a733-preflash-current/boot/extlinux/extlinux.conf`
- 首次 v001 rescue 登录状态：
  `test_files/mainline/01_initial_overlay_validation/log/rescue-login-state.txt`
- Radxa rsetup 与 `u-boot-update` 机制摘录：
  `test_files/mainline/01_initial_overlay_validation/log/rsetup-overlay-mechanism.txt`
- 首次从 `l0r` 回滚 v001 的完整输出：
  `test_files/mainline/01_initial_overlay_validation/tools/rollback-v001-from-l0r.txt`
- 后续受保护的自动回滚脚本：
  `test_files/mainline/02_reflash_handoff/tools/scripts/rollback-versioned-overlay-from-rescue.sh`
- U-Boot 和回滚操作手册：
  `test_files/mainline/02_reflash_handoff/docs/UBOOT_RESCUE_AND_ROLLBACK.md`
