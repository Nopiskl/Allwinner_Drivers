# t4 重刷后的验证与复现流程

## 阶段 0：烧录

SD/eMMC 使用：

```text
radxa-a733_trixie_kde_t4.output_512.img.xz
```

烧录前后校验 SHA-512，值见 `T4_IMAGE_METADATA.md`。

不要把旧 R6 的 extlinux、DTBO、DTB 或 Meizu DKMS 包写入新系统。

## 阶段 1：原厂登录前基线

保持 Meizu overlay 未启用。串口从上电开始完整记录。

观察并记录：

- U-Boot/boot0/SCP/ARISC 版本；
- extlinux 菜单实际标签、默认项和超时；
- HDMI 登录界面是否正常；
- 心跳灯；
- DSI 物理屏在无 overlay 条件下是否保持关闭；
- 启动到登录界面的时间。

不要在这一阶段运行 `rsetup` 修改 overlay。

## 阶段 2：原厂桌面基线

从 HDMI 登录一次桌面，等待至少 3 分钟。记录：

- HDMI 是否蓝屏、闪屏或只有指针；
- SSH 是否仍可调度；
- `sunxi_de_atomic_flush timeout`、IOMMU 和 RCU 计数；
- DRM connector/CRTC 状态；
- Plasma 使用 X11 还是 Wayland。

运行：

```sh
sh remote-new-image-baseline.sh
sh remote-count-display-faults.sh
```

输出保存到新的：

```text
test_files/mainline/03_new_kernel_overlay_validation/log/stock-snapshot/
```

至少完成 3 次冷启动。只要 stock HDMI 自身出现 DE/IOMMU fault，就停止 overlay
适配，先处理 t4 平台基线问题。

## 阶段 3：确认新系统实际机制

只读检查：

```sh
uname -a
cat /etc/os-release
cat /etc/radxa_image_fingerprint
dpkg-query -W linux-image-radxa-a733 u-boot-radxa-a733 radxa-overlays-dkms
command -v rsetup
command -v u-boot-update
cat /etc/default/u-boot
cat /boot/extlinux/extlinux.conf
find /boot/dtbo -maxdepth 1 -type f -printf '%f\n' | sort
find /usr/lib/linux-image-* -name '*cubie-a7a*.dtb' -print
```

预期包版本是 6.6.98-3、U-Boot 2026.04-2、overlay 0.2.25，但以板端实际结果
为准。

## 阶段 4：重新建立 overlay 源

优先级：

1. t4 板端安装的 A7A 8HD/10FHD overlay；
2. 与该包版本对应的 Radxa 官方仓库 tag/commit；
3. 本工作区官方主线仓库，仅用于比较；
4. 历史 v001/v002/v003，仅用于提取 Meizu 已证实参数。

本地 `radxa-overlays-official` 当前是 0.2.28 主线，比 t4 镜像内的 0.2.25
更新，不能不经比较直接混用。

重新编译必须使用 t4 的：

- 内核 headers；
- dt-bindings；
- 基准 Cubie A7A DTB；
- `dtc`/`fdtoverlay`。

每个候选必须：

```text
预处理 DTSO
→ dtc -@
→ 反编译回读
→ fdtoverlay 与 stock DTB 离线合并
→ 检查 DSI/PHY/TCON graph、endpoint、flags、GPIO
→ 记录 SHA-256
```

旧 `meizu-e3-dkms_0.1.10_all.deb` 的 `.ko` 和 postinst 都面向 5.15，禁止直接
安装到 6.6。驱动源可以移植，但必须针对新内核重新构建。

## 阶段 5：按 DSI → I2C → 触摸顺序

### 5A：DSI-only

- 采用官方 A7A Display graph/metadata。
- 只加入 Meizu 已有证据支持的 panel timing、init sequence 和 reset。
- 暂不加入 SGM37604A、SEC 触摸和 `i2c-gpio`。
- 不关闭 HDMI 节点，不修改内核驱动。
- 先验证登录前，再验证一次桌面登录。

如果登录后出现第一次 atomic timeout，立即保存日志并停止继续压力测试。

### 5B：背光/I2C

只有 5A 多次启动无 DE/IOMMU fault 后才加入：

- 与实体接线一致的 I2C bus/GPIO；
- SGM37604A；
- HWEN、LED channel、最大电流和亮度默认值。

先读回寄存器和 sysfs，不先加入触摸。

### 5C：SEC 触摸

背光稳定后再加入 SEC 触摸节点和 6.6 对应驱动。先验证 IRQ/I2C，再做桌面
坐标映射。触摸映射属于用户空间显示布局，不应写进设备树。

## 阶段 6：独立双屏

当 DRM 能稳定暴露 HDMI 与 DSI 两个 connector/CRTC 后，独立桌面布局由
Plasma/KScreen 配置，不需要为了“左右扩展”修改设备树。

先保存无 KScreen 用户配置的基线，再设置左右排列；每次布局切换前后统计：

```text
sunxi_de_atomic_flush timeout
PageTable Invalid
Bug is in DE
RCU stall
```

## 终止条件

出现以下任意一项就不继续叠加新变量：

- 第一个 `sunxi_de_atomic_flush timeout`；
- `PageTable Invalid` 或 `Bug is in DE`；
- 心跳停止或 SSH 无法调度；
- DSI configuration 未完成；
- 多次冷启动结果不一致。

保存串口和 persistent journal，物理重启进入无 overlay 的 rescue entry，再用
版本化回滚脚本禁用当轮候选。
