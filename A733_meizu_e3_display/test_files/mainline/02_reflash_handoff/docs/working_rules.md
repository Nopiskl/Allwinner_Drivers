# Radxa A7A + Meizu E3 后续工作规范

更新时间：2026-08-01

本文件是后续适配、部署和调试的硬约束。除非用户明确改变要求，否则不得绕过。

## 1. 官方实现优先

- 以 Radxa 官方 `radxa-overlays` 仓库中的 Cubie A7A DSI overlay 为结构基线：
  - `cubie-a7a-radxa-display-8hd.dtso`
  - `cubie-a7a-radxa-display-10fhd.dtso`
- 保留官方已经验证的显示拓扑、OF graph、DSI host/PHY/TCON 组织、pinctrl、电源与 overlay metadata 方式。
- 只替换 Meizu E3 硬件确实不同且已有证据支持的项目：
  - 1080×2160 面板时序；
  - 面板 reset GPIO；
  - SGM37604A 背光芯片及 HWEN；
  - SEC 触摸控制器；
  - 由原手机硬件资料或成功运行状态证明必需的 DSI 初始化命令。
- 不凭猜测增加 DSI mode flag、私有 bit、延时、GPIO 极性或驱动参数。
- 不为适配 overlay 主动修改内核 DRM/DSI 驱动。只有在官方式 overlay 已验证、日志证明是内核缺陷、并且用户明确要求后，才讨论内核补丁。
- 每轮只改变一个可归因变量；修改前记录基线，修改后做多次冷启动验证。

## 2. 可验证、可切换、可回退

- 先检查干净系统当前的 `rsetup`、`u-boot-update`、`extlinux.conf` 和 `/boot/dtbo` 实际机制，再制定部署脚本，不照搬旧镜像流程。
- 不直接覆盖唯一的活动 DTBO。每个候选使用版本化文件名和 SHA256，例如：

  ```text
  cubie-a7a-meizu-e3-display-v001.dtbo
  cubie-a7a-meizu-e3-display-v002.dtbo
  ```

- 编译后必须先完成：
  - DTS/DTSO 语法检查；
  - DTBO 反编译回读；
  - overlay 对基准 DTB 的离线合并验证；
  - 关键节点和 phandle/endpoint 检查；
  - 源文件与产物 SHA256 记录。
- 配置更新必须先备份、后生成临时文件、校验成功后再原子替换。
- 不先移动或删除仍被启动配置引用的 DTBO。
- 保留一个不应用 Meizu overlay 的 stock 启动入口，以及一个测试入口；不能让测试 overlay 成为唯一可启动路径。
- 在 U-Boot 菜单或官方支持的等价机制中能够动态选择 stock/test，测试失败时无需再次拆盘即可回退。
- 重启前必须保存本轮配置与日志。重启后先验证实际加载的 DTB/overlay，再进行图形压力测试。
- 涉及物理断电、U-Boot 菜单、`l0r`、救援登录或现场屏幕确认时，先向用户说明
  目标和应选入口，由用户手动进入并通知已经完成；除非用户当次明确要求，不再
  自动发送 U-Boot 菜单按键。
- 离线操作存储设备时必须核对挂载点、分区、UUID和整盘设备；只有确认卸载成功后才执行：

  ```text
  udisksctl power-off -b /dev/sdX
  ```

- 不重复执行未经幂等设计的 `mv`、删除或覆盖命令。

## 3. 记录与证据

- 主结论持续追加到：
  - `docs/FINAL_CONCLUSION.md`
- 每轮测试建立独立目录：

  ```text
  test_files/mainline/NN_简短说明/
  ├── log/
  ├── docs/
  ├── tools/
  └── src/
  ```

- 每轮至少保存：
  - `docs/README.md`：目的、唯一变量、操作、结果、结论；
  - `uname.txt`、内核/overlay/rsetup/DKMS 软件包版本；
  - 修改前后的启动配置；
  - 使用的 `.dtso`、`.dtbo` 及 SHA256；
  - 基准 DTB 与离线合并后的 DTS；
  - 串口完整日志；
  - `dmesg`、`journalctl -b` 和上一启动日志；
  - DRM state、connector/mode、backlight、touch/input 状态；
  - 冷启动次数、成功次数、失败表现和首次异常时间。
- 不用“屏幕此刻亮了”作为修复结论。必须结合多次冷启动和错误计数判断。
- 每次板端写操作前说明将修改什么、如何回退；写操作后记录实际结果，不把计划当成已完成。

## 4. 下一次连接后的顺序

1. 只读采集重刷后的 stock 基线。
2. 检查官方 `rsetup` overlay 管理和启动项生成机制。
3. 核对 kernel、DTB、`radxa-overlays-dkms`、AIC 驱动版本与完整性。
4. 从官方 A7A Display overlay 派生第一版 Meizu DTSO。
5. 第一版只包含已有硬件证据和官方 graph 修复，不加入 DSI-only debug overlay，不关闭 HDMI 子组件。
6. 建立 stock/test 双入口和一键回退，再部署测试。

## 5. 当前排除项

- 用户于 2026-07-31 明确说明：新 t4 串口启动初期可能出现电源、供电或
  regulator 相关告警，该类输出暂时不属于本项目分析范围，后续也不应据此改变
  DSI/overlay 测试方向。
- 除非用户之后明确改变要求，或日志出现能够直接证明电源告警与本次显示故障
  同一时间、同一调用链相关的新证据，否则不把这些告警列入故障候选、统计或
  停止条件。
