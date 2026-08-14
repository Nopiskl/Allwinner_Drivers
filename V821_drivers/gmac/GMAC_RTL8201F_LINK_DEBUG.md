# V821 perf2b GMAC/RTL8201F 链路异常排查记录

## 1. 问题摘要

板端启用 `gmac0` 后，最初执行 `ifconfig` 看不到 `eth0`。手动执行
`ifconfig eth0 up` 后可以识别 RTL8201F，但网线插入后 `carrier` 一直为
`0`，DM5 指示灯持续闪烁，无法建立链路。

本次排查确认：GMAC 驱动、MDIO、PHY 地址、RMII 时钟和基本连线均可工作；
直接故障是 RTL8201F 被配置/采样成了 **100Base-FX 光纤模式**，而板端连接的
是 RJ45 铜缆，应工作在 **10/100Base-T UTP 模式**。

运行时清除 FXMODE 后，10M 和 100M 均能稳定建立链路。目前实测恢复为：

```text
carrier=1
operstate=up
speed=100
duplex=full
Link is Up - 100Mbps/Full
RX errors=0, dropped=0
```

本次切换没有升级固件；运行时配置在重启或 PHY 重新复位后可能丢失。

## 2. 硬件及软件环境

| 项目 | 实际信息 |
| --- | --- |
| SoC/板型 | V821 / perf2b |
| MAC | `gmac0`，控制器地址 `44500000.gmac` |
| MDIO | `44500048.mdio` |
| PHY | Realtek RTL8201F，PHY ID `001c:c816` |
| PHY 地址 | `0` |
| 接口模式 | RMII |
| PHY 复位 | `PD17`，低有效 |
| 设备树最高速率 | `max-speed = <100>` |

相关文件：

- `device/config/chips/v821/configs/perf2b/board.dts`（符号链接）
- `device/config/chips/v821/configs/perf2b/linux-5.4-ansc/board.dts`
- `device/config/chips/v821/configs/perf2b/quick_config.json`
- `device/config/chips/v821/configs/perf2b/V821M2-WXX_PER2_B_4L_V1_0-20250115.原理图.pdf`

## 3. 初始现象及判断

### 3.1 `ifconfig` 看不到 `eth0`

不带参数的旧版 `ifconfig` 通常只显示已经 UP 的接口，因此这不等同于驱动
没有注册。应先执行：

```sh
ifconfig -a
ls -l /sys/class/net
ifconfig eth0 up
dmesg | grep -E "gmac|eth0|PHY|mdio"
```

本次手动 UP 后出现以下日志，说明 MAC、MDIO 和 PHY 探测成功：

```text
sunxi:gmac-44500000.gmac:[INFO]: eth0: Type(7) PHY ID 001cc816 at 0 IRQ poll (44500048.mdio-mii:00)
```

### 3.2 指示灯闪烁但 `carrier=0`

DM5 的原理图标注是 `100M Link/Receive/Transmit`，但 LED 闪烁不能代替链路
状态判断。诊断时应以以下接口为准：

```sh
cat /sys/class/net/eth0/carrier
cat /sys/class/net/eth0/operstate
cat /sys/class/net/eth0/speed
cat /sys/class/net/eth0/duplex
```

`carrier=0` 表示物理链路并未建立，即使 LED 正在闪烁也不能认为链路正常。

## 4. 已确认的直接故障

故障状态下读取到的关键 PHY 寄存器如下：

| 页/寄存器 | 故障值 | 含义 |
| --- | ---: | --- |
| Page 0 / Reg 0 (BMCR) | `0x2100` | 100M、全双工、自动协商关闭 |
| Page 0 / Reg 28 | `0x40e2` | Bit 5 `FXMODE=1` |
| Page 7 / Reg 16 | `0x0ffa` | RMII 接口配置存在且可读 |

RTL8201F 的 Page 0 Reg 28 Bit 5 是 FXMODE：

- `FXMODE=1`：100Base-FX 光纤模式；
- `FXMODE=0`：10/100Base-T UTP 铜缆模式。

进入 FX 模式后，BMCR 的速率固定为 100M，自动协商关闭。因此此前看到的
`0x2100` 虽然包含“100M”，实际含义是 **100Base-FX**，并不是 RJ45 所需的
**100Base-TX**。这也解释了为什么修改 BMCR 的 10M/自动协商位会被忽略或
无法得到稳定结果。

将 Reg 28 从 `0x40e2` 改为 `0x40c2`，即只清除 Bit 5 后，铜缆链路可以正常
建立。这是本次已经通过板端实测确认的直接原因。

## 5. FXMODE 被错误置位的已确认来源

RTL8201F 在复位释放时会通过 `RXER/FXEN` 引脚采样介质模式：低电平选择 UTP，
高电平选择 Fiber。

### 5.1 原理图中的完整连接关系

结合原理图第 9 页的 LCD/CTP 复用电阻和第 11 页的 RTL8201F 接口电阻，实际
信号链如下：

```text
VCC33-PD
   |
 RA27 2K（实际已焊接）
   |
 CTP-INT
   |
 RA38 0R（实际已焊接）
   |
 RMII-RXER / SoC PD8
   |
 RM37 0R
   |
 ARMII-RXER / RTL8201F RXER/FXEN
   |
 RM22 4.7K
   |
  GND
```

其中：

- 原理图第 9 页将 `RA27` 标成 `NC/2K`，用于把 `CTP-INT` 上拉至
  `VCC33-PD`；
- `RA38` 标成 `NC/0R`，用于把 `CTP-INT` 选择性连接到复用的
  `RMII-RXER/PD8`；
- 第 11 页的 `RM37=0R` 把 `RMII-RXER` 接到 PHY 的
  `ARMII-RXER/RXER/FXEN`；
- `RM22=4.7K` 是 UTP 模式下拉，`RM23=NC/4.7K` 是 Fiber 模式上拉选件。

图纸上的“所有同线选焊电阻并排放置”说明这些电阻是功能选择位。GMAC 模式
不应同时焊接把 CTP-INT 接入该网络的 RA27 和 RA38。

### 5.2 RA27 与 RM22 形成分压

RA27 和 RA38 都焊接后，RM22 不再是唯一的外部偏置。忽略弱内部偏置并假设
`VCC33-PD=3.3V`，复位采样时的标称电压为：

```text
V(RXER/FXEN) = 3.3V * 4.7K / (2K + 4.7K)
              = 2.32V

I = 3.3V / (2K + 4.7K)
  = 0.49mA
```

也就是说，2K 上拉比 4.7K 下拉更强，节点不是可靠低电平，而是被偏置到约
`0.70 * VCC`。本板实际读取到 `Reg28=0x40e2`，其中 FXMODE Bit 5 为 1，
已经证明 RTL8201F 在复位采样时把该节点识别成了高电平。

随后仅将 Reg 28 从 `0x40e2` 改为 `0x40c2`，RJ45 立即恢复 100Base-TX；这与
原理图分压计算形成完整证据链。因此最终根因确认如下：

> RA27=2K 和 RA38=0R 被同时焊接，将 CTP-INT 的强上拉接入
> RMII_RXER/RXER/FXEN；该上拉压过 RM22=4.7K 的 UTP 下拉，使 RTL8201F
> 在复位释放时采样为 Fiber 模式。

### 5.3 设备树上拉的叠加影响

当前设备树把 `PD1` 到 `PD11` 的全部 RMII 引脚统一配置为上拉：

```dts
gmac0_pins_default: gmac_pins@0 {
	pins = "PD1", "PD2", "PD3",
		"PD4", "PD5", "PD6", "PD7",
		"PD8", "PD9", "PD10", "PD11";
	function = "rmii";
	allwinner,muxsel = <4>;
	allwinner,drive = <3>;
	bias-pull-up;
};
```

V821 的 `PD8` 对应 `RMII_RXER`，它连接到 RTL8201F 的 `RXER/FXEN`。运行时
pinconf 也确认 PD8 处于 pull-up。它会进一步把采样电平推向高，但相对于外部
RA27 的 2K 上拉，它是次要因素。永久修改时仍应把 PD8 从统一上拉组中拆出，
配置为无内部上拉或合适的下拉；不要把其他 RMII 引脚未经分析地全部改成下拉。

### 5.4 装配选择建议

GMAC 模式的合理装配关系为：

- 保留 `RM37=0R`，连接 SoC PD8 与 RTL8201F；
- 保留 `RM22=4.7K` 下拉，保持 `RM23` 不贴；
- 移除 `RA38`，彻底隔离 CTP-INT 分支；
- RA27 可以为 CTP 侧保留，但不得再通过 RA38 接入 RMII_RXER。

只移除 RA27 虽然能消除 2K 上拉，但 RA38 仍会把 CTP-INT 与 PHY 的 RXER 输出
直接相连。触摸控制器拉低中断时可能注入错误 RXER，PHY 输出 RXER 时也可能与
触摸端发生电气冲突。因此 GMAC 模式应优先断开 RA38。若 GMAC 与触摸中断必须
同时工作，CTP-INT 需要改接其他空闲 GPIO。

## 6. 不升级固件的临时恢复方法

仓库提供了一个可直接下发到板端的最小恢复脚本：

```text
device/config/chips/v821/configs/perf2b/gmac_recover.sh
```

PC 端执行：

```sh
adb push device/config/chips/v821/configs/perf2b/gmac_recover.sh /tmp/
adb shell chmod +x /tmp/gmac_recover.sh
adb shell /tmp/gmac_recover.sh
```

脚本会先校验 PHY ID 必须为 `001c:c816`，再动态读取 Reg 28、只清除 FXMODE
Bit 5，然后恢复 10/100M 自动协商并等待 carrier。它不配置 IP，也不会写入
Flash；由于硬件 strap 仍然存在，每次冷启动或 PHY 硬复位后都需要重新执行。

### 6.1 MDIO sysfs 使用注意

板端驱动提供：

```text
/sys/bus/platform/devices/44500048.mdio/mii_read
/sys/bus/platform/devices/44500048.mdio/mii_write
```

`mii_read` 输入两个十六进制参数：`PHY地址 寄存器地址`。

`mii_write` 输入三个十六进制参数：`PHY地址 寄存器地址 值`。该驱动在
`echo` 时只保存参数，随后执行 `cat mii_write` 才真正完成写入，因此每次
写操作后都必须紧跟一次 `cat`。

可定义两个辅助函数：

```sh
P=/sys/bus/platform/devices/44500048.mdio

mdio_read()
{
	echo "0 $1" > "$P/mii_read"
	cat "$P/mii_read"
}

mdio_write()
{
	echo "0 $1 $2" > "$P/mii_write"
	cat "$P/mii_write"
}
```

### 6.2 清除 FXMODE 并重新协商

```sh
ifconfig eth0 up

P=/sys/bus/platform/devices/44500048.mdio

# 选择 Page 0
echo "0 1f 0000" > "$P/mii_write"
cat "$P/mii_write"

# Reg 28: 0x40e2 -> 0x40c2，清除 FXMODE Bit 5
echo "0 1c 40c2" > "$P/mii_write"
cat "$P/mii_write"

# 通告 10/100M、半/全双工及流控能力
echo "0 04 0de1" > "$P/mii_write"
cat "$P/mii_write"

# 开启并重新启动自动协商；restart 位会自动清零
echo "0 00 1200" > "$P/mii_write"
cat "$P/mii_write"
```

等待约 3～5 秒后检查：

```sh
cat /sys/class/net/eth0/carrier
cat /sys/class/net/eth0/speed
cat /sys/class/net/eth0/duplex
dmesg | grep "eth0: Link" | tail
```

注意：如果之前已经通过 ethtool ioctl 把内核 `phydev->advertising` 缓存限制为
仅 10M，直接写 MDIO 寄存器可能随后被 PHY 状态机覆盖。此时应使用 ethtool
或能够调用 `ETHTOOL_SSET`/link-ksettings 的工具同步恢复自动协商能力。本次
板端最终通过临时工具执行以下命令后稳定恢复 100M：

```sh
/tmp/phyctl eth0 autoall
```

`/tmp/phyctl` 是本次调试临时下发的程序，重启后不保证存在。

## 7. 10M/100M 测试结果

### 7.1 10M 测试

清除 FXMODE 并把自动协商能力限制为 10M 后，实测结果：

```text
carrier=1
speed=10
duplex=full
Reg 0 = 0x1100
Reg 4 = 0x0061
Reg 28 = 0x40c2
RX errors=0
```

### 7.2 恢复 100M

恢复全部自动协商能力后，约 4 秒建立链路并持续稳定：

```text
carrier=1
operstate=up
speed=100
duplex=full
advertising=0x000062cf
Link is Up - 100Mbps/Full - flow control rx/tx
RX packets=120, errors=0, dropped=0
```

这证明 PHY、RMII、网线和对端设备能够工作在 100Base-TX，全双工 100M 本身
没有硬件能力问题。

## 8. 永久修复建议

建议按以下顺序处理：

1. GMAC 模式移除 RA38，使 CTP-INT/RA27 上拉与 RMII_RXER 隔离；
2. 保留 RM22=4.7K 下拉、RM37=0R，并保持 RM23 不贴；
3. 在设备树中把 `PD8/RMII_RXER` 从统一 `bias-pull-up` pinctrl 中拆出，单独
   配置为下拉或无内部上拉；
4. 使用示波器确认 RTL8201F 复位释放瞬间 `RXER/FXEN` 为低；
5. 冷启动后读取 Page 0 Reg 28，确认 Bit 5 默认就是 0，而不是依赖启动脚本
   再清除；
6. 连续冷启动、热重启和反复插拔网线，检查是否始终协商为 100Mbps/Full；
7. 使用 `ping` 和 `iperf3` 做收发压力测试，并检查错误计数。

`max-speed = <100>` 只是声明 PHY 的最高能力为 100M，不会强制 100M，也不会
导致 FX 模式。推荐保留自动协商，让双方选择 100M/Full，不建议仅在一端强制
100M/Full，否则可能产生双工不匹配。

## 9. 其他配置冲突及注意事项

### 9.1 GMAC 与 DBI 屏引脚复用

DBI 屏配置使用 `PD1`、`PD2`、`PD3`、`PD5`、`PD6`，而 GMAC RMII 使用
`PD1`～`PD11`，两者不能同时占用这些引脚。`quick_config.json` 中相应 DBI
屏配置会将 `phy0`、`mdio0` 和 `gmac0` 设为 `disabled`，这是预期的互斥切换，
不是本次 FXMODE 故障。

### 9.2 PD17 复用风险

当前设备树同时把 PD17 用作 `phy0` 的低有效复位 GPIO 和 LCD 的
`lcd_gpio_2`。如果两个设备同时启用，需要确认 LCD 初始化不会再次拉低 PHY
复位信号；正式配置中应避免两个驱动同时控制同一 GPIO。

### 9.3 MTU 950

调试时 `eth0` 显示 `MTU:950`。这与物理层无法建立 carrier 无关，但可能影响
后续吞吐测试或较大报文。链路问题解决后，应根据产品网络配置确认是否需要
恢复为常见的 1500：

```sh
ifconfig eth0 mtu 1500
```

## 10. 复测检查表

```sh
ifconfig eth0 up

cat /sys/class/net/eth0/carrier
cat /sys/class/net/eth0/operstate
cat /sys/class/net/eth0/speed
cat /sys/class/net/eth0/duplex

ifconfig eth0
dmesg | grep -E "PHY ID|eth0: Link" | tail -n 20

P=/sys/bus/platform/devices/44500048.mdio
echo "0 1f 0000" > "$P/mii_write"; cat "$P/mii_write"
echo "0 1c" > "$P/mii_read"; cat "$P/mii_read"
```

合格标准：

- PHY ID 稳定识别为 `001c:c816`；
- Page 0 Reg 28 Bit 5 为 0（本次正常值为 `0x40c2`）；
- 插线后 `carrier=1`、`speed=100`、`duplex=full`；
- 日志没有持续 Link Up/Down 抖动；
- RX/TX errors、dropped、carrier errors 不持续增长；
- 冷启动和热重启后无需手工写寄存器即可恢复链路。
