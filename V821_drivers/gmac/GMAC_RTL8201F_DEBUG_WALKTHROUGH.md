# V821 GMAC/RTL8201F 调试过程复盘与命令解析

> 记录日期：2026-08-13<br>
> 调试对象：V821 perf2b、sunxi GMAC、RTL8201F、RMII、RJ45 铜缆<br>
> 配套结论文档：[GMAC_RTL8201F_LINK_DEBUG.md](./GMAC_RTL8201F_LINK_DEBUG.md)

## 1. 文档目的

这份文档按实际调试顺序复盘，不只记录“执行了什么”，还记录：

- 为什么执行这条命令；
- 看到了什么现象；
- 现象可以证明什么、不能证明什么；
- 如何从一个假设转向下一个假设；
- 哪些尝试没有按预期生效，以及为什么；
- 如何用最小改动验证根因。

最终结论是：RTL8201F 被置于 100Base-FX 光纤模式。清除 Page 0 Reg 28 的
FXMODE Bit 5 后，RJ45 所需的 10/100Base-T 铜缆模式恢复，10M 和 100M 均可
建立稳定链路。

## 2. 调试思路：从软件上层逐层下钻

以太网接口不可用时，可以按下面的层次排查：

```text
接口是否注册
    ↓
MAC 驱动是否 probe
    ↓
MDIO 是否能读到 PHY ID
    ↓
PHY 复位、供电、参考时钟是否正常
    ↓
RMII pinmux 和引脚复用是否正确
    ↓
PHY 介质模式、strap 和自动协商是否正确
    ↓
carrier、速率和双工是否建立
    ↓
IP、ping、吞吐和丢包测试
```

本次调试遵循这个顺序。这样能避免一开始就修改 `tx-delay`、`rx-delay` 或
IP 配置，而忽略更底层的 PHY 模式错误。

## 3. 第一步：ADB 重连并确认设备在线

板端中途发生过重启，因此先确认 ADB，而不是直接假设之前的运行时状态仍然
存在。

```sh
adb devices
adb wait-for-device
adb shell uname -a
```

实测设备序列号：

```text
7c000c70f6c2885200f    device
```

分析：

- `device` 表示 ADB 通道可用；
- `adb wait-for-device` 适合放在调试脚本开头，板端重启后会等待重新上线；
- PHY 寄存器修改和 `/tmp` 下的临时工具都可能因重启丢失，不能沿用重启前的
  假设。

## 4. 第二步：确认 `eth0` 是否真的不存在

最初不带参数执行 `ifconfig`，只看到 `lo` 和 `wlan0`：

```sh
ifconfig
```

此时不能直接判断 GMAC 驱动失败，因为旧版 `ifconfig` 默认只显示已经 UP 的
接口。继续执行：

```sh
ifconfig -a
ls -l /sys/class/net
```

然后主动拉起接口：

```sh
ifconfig eth0 up
```

板端日志出现：

```text
sunxi:gmac-44500000.gmac:[INFO]: eth0: Type(7) PHY ID 001cc816 at 0 IRQ poll (44500048.mdio-mii:00)
```

分析：

- `eth0` 已经被网络子系统注册；
- GMAC 驱动已经 probe；
- MDIO 总线能读到 PHY；
- PHY 地址为 0；
- PHY ID 为 `001c:c816`，与 RTL8201F 相符；
- 因此问题范围从“驱动没有加载”缩小到“PHY 建链阶段”。

## 5. 第三步：区分接口 UP 与物理链路 UP

接口拉起后执行：

```sh
cat /sys/class/net/eth0/carrier
cat /sys/class/net/eth0/operstate
cat /sys/class/net/eth0/speed
cat /sys/class/net/eth0/duplex
ifconfig eth0
```

初始现象：

```text
carrier=0
eth0: UP BROADCAST MULTICAST
```

分析：

- `ifconfig eth0 up` 只代表管理状态为 UP；
- `carrier=0` 才是 PHY 尚未检测到有效物理链路的关键证据；
- 没有 carrier 时，先排查 PHY、时钟、介质模式和协商，不应先排查 DHCP；
- DM5 持续闪烁不能代替 carrier 判断，LED 可能反映链路脉冲、活动或异常模式。

连续监控命令：

```sh
for i in 0 1 2 3 4 5 6 7 8 9; do
	printf "t=%02ss carrier=" "$i"
	cat /sys/class/net/eth0/carrier
	printf "speed="
	cat /sys/class/net/eth0/speed
	printf "duplex="
	cat /sys/class/net/eth0/duplex
	sleep 1
done
```

## 6. 第四步：确认运行中的设备树，而不只看源码

源码中的 DTS 正确不代表烧入板端的 DTB 一定相同，因此读取运行时设备树：

```sh
DT=/sys/firmware/devicetree/base/soc@2002000

printf "gmac.status="
tr -d '\000' < "$DT/gmac@44500000/status"
echo

printf "gmac.phy-mode="
tr -d '\000' < "$DT/gmac@44500000/phy-mode"
echo

printf "mdio.status="
tr -d '\000' < "$DT/mdio@44500048/status"
echo

printf "phy.status="
tr -d '\000' < "$DT/mdio@44500048/ethernet-phy@0/status"
echo

printf "phy.compatible="
tr '\000' ' ' < "$DT/mdio@44500048/ethernet-phy@0/compatible"
echo
```

实测：

```text
gmac.status=okay
gmac.phy-mode=rmii
mdio.status=okay
phy.status=okay
phy.compatible=ethernet-phy-id001c.c816
```

分析：运行中的 DTB 确实启用了 GMAC、MDIO 和 PHY，接口模式也是 RMII，排除
了“只改了源码但没有生效”以及节点仍为 `disabled` 的情况。

## 7. 第五步：检查 PHY 复位、参考时钟和 pinctrl

### 7.1 PHY 复位 GPIO

挂载 debugfs 后检查 GPIO：

```sh
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
grep -i -E "PHY reset|PD17" /sys/kernel/debug/gpio
```

实测：

```text
gpio-113 (... |PHY reset) out hi ACTIVE LOW
```

分析：PD17 是低有效复位，当前输出高表示 PHY 已退出复位。能稳定读取 PHY ID
也从侧面证明 PHY 不是一直处于复位状态。

### 7.2 RMII 参考时钟

```sh
grep -i -E "gmac|ephy|25m|rmii" /sys/kernel/debug/clk/clk_summary
```

实测关键项：

```text
gmac-27m       ... 25000000
gmac-fanout    ... 25000000
```

分析：SoC 侧存在实际 25 MHz 时钟输出。虽然节点名称含 `27m`，但
`clk_summary` 中的实际速率是 25 MHz，应以数值为准。时钟存在后，不再把
“完全没有 PHY 参考时钟”作为首要假设。

### 7.3 RMII pinmux

```sh
for f in /sys/kernel/debug/pinctrl/*/pinmux-pins \
         /sys/kernel/debug/pinctrl/*/pinconf-pins; do
	[ -f "$f" ] || continue
	grep -E "PD(1|2|3|4|5|6|7|8|9|10|11)([^0-9]|$)" "$f"
done
```

实测 `PD1`～`PD11` 都归属 `44500000.gmac`、function 为 `rmii`，同时全部
显示 `input bias pull up`。

分析分为两部分：

1. pinmux 已切到 GMAC，不是仍被 DBI、LCD、SDC 或 Wi-Fi 占用；
2. 所有 RMII 引脚统一上拉值得怀疑，因为其中可能包含 PHY 上电 strap 信号。

此时“统一上拉”只是线索，尚不能直接下结论，需要结合 PHY 寄存器和原理图。

## 8. 第六步：通过 MDIO 读取 PHY 寄存器

板端没有 `ethtool` 和 `mii-tool`，但 sunxi MDIO 驱动提供了 sysfs 调试接口：

```text
/sys/bus/platform/devices/44500048.mdio/mii_read
/sys/bus/platform/devices/44500048.mdio/mii_write
```

定义辅助函数：

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

这个驱动的 sysfs 行为比较特殊：

- `mii_read` 的格式是两个十六进制参数：`PHY地址 寄存器`；
- `mii_write` 的格式是三个参数：`PHY地址 寄存器 值`；
- 对 `mii_write` 执行 `echo` 只是保存参数；
- 随后的 `cat mii_write` 才会执行实际写入并打印写入前后的值。

这一行为可以在 `bsp/drivers/gmac/sunxi-mdio.c` 的
`sunxi_mdio_write_store()` 和 `sunxi_mdio_write_show()` 中确认。

读取标准寄存器和 RTL8201F Page 0 Reg 28：

```sh
mdio_write 1f 0000
mdio_read 00
mdio_read 01
mdio_read 01
mdio_read 04
mdio_read 05
mdio_read 1c
```

Reg 1/BMSR 建议连续读取两次，因为部分 PHY 的链路位具有 latched-low 特性，
第一次可能返回历史状态，第二次更接近当前状态。

故障状态的关键结果：

```text
Reg 0  = 0x2100
Reg 28 = 0x40e2
```

## 9. 第七步：先解码 BMCR，再追查“为什么写不动”

BMCR/Reg 0 的 `0x2100` 可以按位拆解：

```text
Mask 0x2000  Bit 13 = 1，100M 选择
Mask 0x0100  Bit 8  = 1，全双工
Mask 0x1000  Bit 12 = 0，自动协商关闭
```

第一眼看起来 PHY 已经是“100M 全双工”，但 RJ45 仍然没有 carrier。尝试把
BMCR 改成自动协商或 10M 后，相关位没有按普通铜缆 PHY 的预期工作，链路也
不稳定。

此时正确的问题不是“继续反复写 Reg 0”，而是：

> 是否存在某个 strap 或厂商寄存器，把标准 BMCR 的行为改变了？

因此转而查 RTL8201F 数据手册，并读取厂商寄存器。Page 0 Reg 28 的
`0x40e2` 中 Bit 5 为 1：

```text
0x40e2 & 0x0020 = 0x0020
```

数据手册说明该位是 FXMODE：

- Bit 5 = 1：100Base-FX 光纤模式；
- Bit 5 = 0：10/100Base-T UTP 模式。

FX 模式下速率固定为 100M，自动协商关闭，因此 Reg 0 表现为 `0x2100` 是
符合数据手册的。之前看到的“100M”实际是 100Base-FX，不是 RJ45 需要的
100Base-TX。

## 10. 第八步：用单变量修改验证根因

为了避免一次修改多个寄存器后无法判断是谁起作用，只清除 Reg 28 Bit 5：

```text
故障值：0x40e2
清 Bit 5：0x40e2 & ~0x0020
正常值：0x40c2
```

板端命令：

```sh
P=/sys/bus/platform/devices/44500048.mdio

# Page 0
echo "0 1f 0000" > "$P/mii_write"
cat "$P/mii_write"

# 只清 FXMODE
echo "0 1c 40c2" > "$P/mii_write"
cat "$P/mii_write"

# 启动自动协商
echo "0 00 1200" > "$P/mii_write"
cat "$P/mii_write"
```

结果：

```text
sunxi-gmac 44500000.gmac eth0: Link is Up - 100Mbps/Full
carrier=1
speed=100
duplex=full
```

分析：只改变 FXMODE 就使 RJ45 的 100Base-TX 链路建立，这是非常强的因果
证据。GMAC、RMII 数据线、PHY 模拟前端、变压器和网线至少具备正常建链能力。

## 11. 第九步：切到 10M 验证 PHY 铜缆模式

板端缺少 ethtool，因此临时交叉编译并通过 ADB 下发了一个基于 ethtool ioctl
的 `/tmp/phyctl`。它可以同步修改 Linux phylib 中的协商配置。

限制为只通告 10M：

```sh
/tmp/phyctl eth0 auto10
```

结果：

```text
carrier=1
speed=10
duplex=full
Reg 0  = 0x1100
Reg 1  = 0x786d
Reg 4  = 0x0061
Reg 5  = 0xcde1
Reg 28 = 0x40c2
RX packets=82, errors=0, dropped=0
```

分析：

- 10M 可以稳定建链，进一步证明当前已退出只能工作在 100M 的 FX 模式；
- 自动协商配置已经进入内核 `phydev->advertising`，不只是写了 PHY 寄存器；
- RX 包计数增加且无错误，说明不仅 carrier 存在，MAC 也收到有效以太网帧。

## 12. 第十步：恢复 100M 时发现内核缓存陷阱

在 10M 测试后，曾直接通过 MDIO 将 ANAR/Reg 4 改为只通告 100M，并重启自动
协商：

```sh
echo "0 04 0181" > "$P/mii_write"; cat "$P/mii_write"
echo "0 00 1200" > "$P/mii_write"; cat "$P/mii_write"
```

寄存器写入成功，但链路最后仍回到 10M。`phyctl get` 显示内核缓存仍然是：

```text
advertising=0x000000c3
```

这个现象说明：

- 直接写 MDIO 改变的是 PHY 硬件寄存器；
- ethtool ioctl 修改的还包括 Linux phylib 的软件状态；
- PHY 状态机后续可能重新配置寄存器，或者按缓存能力解析协商结果；
- 因此通过 ioctl 设置过速率后，不应只依赖裸 MDIO 写入恢复。

随后通过 ioctl 同步恢复全部支持能力：

```sh
/tmp/phyctl eth0 autoall
```

刚执行时链路断开并重新协商：

```text
after: speed=unknown, autoneg=on, advertising=0x000062cf
t=0s  carrier=0
t=1s  carrier=0
t=2s  carrier=0
t=3s  carrier=0
t=4s  carrier=1, speed=100, duplex=full
```

随后 100M/Full 持续稳定，日志为：

```text
Link is Up - 100Mbps/Full - flow control rx/tx
```

这一步的学习点是：硬件寄存器状态和内核保存的链路配置是两个层次，调试时
必须确认二者一致。

## 13. 第十一步：从原理图和装配确认 FXMODE 来源

确认直接原因后，继续追查为什么每次 PHY 复位后会进入 FX 模式。

### 13.1 SoC 引脚对应关系

原理图和 V821 pinctrl 信息表明：

```text
PD8 <-> RMII_RXER <-> RTL8201F RXER/FXEN
```

当前设备树把 `PD1`～`PD11` 统一配置为：

```dts
bias-pull-up;
```

运行时 pinconf 也确认 PD8 是 `input bias pull up`。而 RTL8201F 会在复位释放
时采样 RXER/FXEN：低为 UTP，高为 Fiber。因此 PD8 上拉是一个明确的配置风险。

### 13.2 原理图第 9 页：CTP-INT 复用支路

第 9 页给出了 PD8/RMII-RXER 与触摸中断的选择焊接关系：

```text
VCC33-PD -- RA27 NC/2K -- CTP-INT -- RA38 NC/0R -- RMII-RXER
```

图纸标注“所有同线选焊电阻并排放置”，说明 RA27/RA38 是 CTP 功能的选择
装配位。实际板上 RA27 和 RA38 均已焊接，因此 `RMII-RXER` 得到了经 2K 电阻
来自 `VCC33-PD` 的强上拉。

### 13.3 原理图第 11 页：PHY strap 支路

原理图第 11 页设计为：

```text
RM22 = 4.7K      ARMII_RXER 下拉，选择 UTP
RM23 = NC/4.7K   上拉位默认不贴，选择 Fiber
```

`RMII-RXER` 还通过 `RM37=0R` 接到 `ARMII-RXER/RXER/FXEN`。把两页原理图
合并后，实际电路为：

```text
VCC33-PD -- RA27 2K -- RA38 0R -- RMII-RXER -- RM37 0R
                                                        |
                                           ARMII-RXER / RXER/FXEN
                                                        |
                                                   RM22 4.7K
                                                        |
                                                       GND
```

忽略内部弱偏置，标称节点电压为：

```text
3.3V * 4.7K / (2K + 4.7K) = 2.32V，约为 0.70 * VCC
```

因此 RM22 虽然存在，2K 上拉和 4.7K 下拉仍然会把 strap 节点分压到高电平
区域。板端读取到 `Reg28=0x40e2/FXMODE=1`，随后清除该位即恢复
100Base-TX，确认了这一分析。

证据强度应明确区分：

| 判断 | 证据等级 | 说明 |
| --- | --- | --- |
| FXMODE=1 导致 RJ45 不建链 | 已确认 | 清 Bit 5 后立即恢复 100Base-TX |
| GMAC/MDIO/PHY 驱动正常 | 已确认 | PHY ID 可读、10M/100M 均可建链 |
| RA27=2K、RA38=0R 均已焊接 | 已确认 | 实际装配状态与原理图复用网络一致 |
| 外部电阻网络把 strap 偏置为高 | 已确认 | 2.32V 分压计算与 FXMODE=1 实测吻合 |
| DTS 的 PD8 pull-up | 已确认的叠加因素 | 会进一步偏高，但弱于外部 2K 上拉 |

这种“已确认事实、强线索、待验证假设”的分层很重要，可以避免把合理怀疑写成
未经验证的最终结论。

对于 GMAC 装配，最干净的硬件处理是移除 RA38，使 CTP-INT 和 RA27 与 RXER
彻底隔离。若硬件暂时无法修改，则每次 PHY 硬复位后运行仓库中的
`device/config/chips/v821/configs/perf2b/gmac_recover.sh` 清除 FXMODE。

## 14. 当前正常状态基线

再次读取板端，当前状态为：

```text
carrier=1
operstate=up
speed=100
duplex=full
mtu=950
```

当前 Page 0 PHY 寄存器：

```text
Reg 0  BMCR = 0x3100
Reg 1  BMSR = 0x786d
Reg 4  ANAR = 0x0de1
Reg 5  LPA  = 0xcde1
Reg 28      = 0x40c2
```

内核链路配置：

```text
speed=100
duplex=full
autoneg=on
supported=0x000062cf
advertising=0x000062cf
lp_advertising=0x0000604f
```

这组数据可以作为以后冷启动或修改 DTS 后的对照基线。

## 15. 常用命令速查

### 15.1 接口、驱动和链路

```sh
ifconfig -a
ifconfig eth0 up
ls -l /sys/class/net

cat /sys/class/net/eth0/carrier
cat /sys/class/net/eth0/operstate
cat /sys/class/net/eth0/speed
cat /sys/class/net/eth0/duplex

dmesg | grep -E "gmac|mdio|PHY ID|eth0: Link"
```

### 15.2 确认 PHY 设备路径

```sh
readlink /sys/class/net/eth0/phydev
```

本板返回：

```text
../../../44500048.mdio/mdio_bus/44500048.mdio-mii/44500048.mdio-mii:00
```

末尾的 `:00` 表示 PHY 地址为 0。

### 15.3 MDIO 寄存器读取

```sh
P=/sys/bus/platform/devices/44500048.mdio

# 切 Page 0。注意 cat 才执行写入
echo "0 1f 0000" > "$P/mii_write"
cat "$P/mii_write"

for reg in 00 01 04 05 1c; do
	echo "0 $reg" > "$P/mii_read"
	cat "$P/mii_read"
done
```

读取 RTL8201F Page 7 Reg 16 后务必切回 Page 0：

```sh
echo "0 1f 0007" > "$P/mii_write"; cat "$P/mii_write"
echo "0 10" > "$P/mii_read"; cat "$P/mii_read"
echo "0 1f 0000" > "$P/mii_write"; cat "$P/mii_write"
```

本次 Page 7 Reg 16 读取值为 `0x0ffa`。

### 15.4 统计和日志观察

```sh
ifconfig eth0
dmesg -w | grep -E "eth0: Link|gmac"
```

重点观察：

- RX/TX packets 是否增长；
- errors、dropped、overruns、carrier 是否增长；
- 是否持续出现 Link Up/Down 抖动。

## 16. 本次调试中的易错点

### 16.1 `ifconfig` 没显示，不等于网卡不存在

先用 `ifconfig -a` 和 `/sys/class/net` 判断是否注册，再决定是否检查驱动。

### 16.2 LED 亮或闪，不等于 carrier 已建立

始终以 `/sys/class/net/eth0/carrier` 和内核 Link Up 日志为准。

### 16.3 BMCR 显示 100M，不等于一定是 100Base-TX

RTL8201F 在 FX 模式下同样显示固定 100M，必须同时检查厂商介质模式寄存器。

### 16.4 `mii_read` 不能传三个参数

正确格式是：

```sh
echo "0 1c" > "$P/mii_read"
cat "$P/mii_read"
```

多传一个值会返回 `write error: Invalid argument`，而之后 `cat` 可能仍显示上次
缓存的寄存器结果，容易误判。

### 16.5 `echo mii_write` 后必须执行 `cat`

这是本驱动特有的 sysfs 实现。只有 `echo` 不会真正写 PHY。

### 16.6 切换 PHY page 后要恢复 Page 0

否则后续读取同一寄存器号时，实际读到的是其他 page，数值会失去可比性。

### 16.7 自动协商 restart 位自动清零是正常的

写 BMCR `0x1200` 后读回不一定仍包含 restart 位，因为该位是自清零控制位。

### 16.8 裸 MDIO 写入与 phylib 缓存可能不一致

临时观察寄存器可以使用 MDIO；正式切换速率优先使用 ethtool/link-ksettings，
让内核状态和硬件状态一起更新。

### 16.9 不建议只在一端强制 100M/Full

如果交换机端仍为自动协商，单端强制可能造成双工不匹配。正常产品配置优先
使用自动协商，并确认最终结果为 100M/Full。

### 16.10 MTU 950 与 `carrier=0` 无关

MTU 属于数据链路层报文大小设置，不会导致 PHY 完全无法建链。它需要在后续
吞吐测试中单独评估，但不应混入物理层根因判断。

## 17. 后续完整验证建议

目前已经验证物理链路、协商速率和接收帧计数。永久修改 DTS 或硬件后，还应
进行：

1. 断电冷启动 20 次，确认 Reg 28 Bit 5 每次都为 0；
2. 热重启 20 次，确认无需手工写 MDIO 即可建立 100M/Full；
3. 反复插拔网线，确认没有持续 Link Up/Down；
4. 用固定 IP 或 DHCP 完成双向 ping；
5. 使用 iperf3 做双向吞吐和长时间稳定性测试；
6. 测试结束后检查 RX/TX errors、dropped 和 carrier errors；
7. 同时启用屏幕相关功能时，复查 PD1～PD11 和 PD17 是否存在资源冲突。

示例网络测试命令如下，IP 地址应按实际测试网络修改：

```sh
# 板端
ifconfig eth0 192.168.10.2 netmask 255.255.255.0 up
ping -c 20 192.168.10.1

# 如果固件包含 iperf3，PC 端先执行 iperf3 -s
iperf3 -c 192.168.10.1 -t 60
iperf3 -c 192.168.10.1 -t 60 -R

ifconfig eth0
```

最终验收不能只看“LED 亮了”或“carrier=1”，还要同时满足速率、双工、双向
收发、错误计数和多次重启一致性要求。

## 18. 相关资料和代码位置

- RTL8201F 数据手册：<https://atta.szlcsc.com/upload/public/pdf/source/20230111/0A7B8DFCF34CFC72D8D907AFD3A59BDF.pdf>
- 板级原理图：`device/config/chips/v821/configs/perf2b/V821M2-WXX_PER2_B_4L_V1_0-20250115.原理图.pdf`
- 当前板级 DTS：`device/config/chips/v821/configs/perf2b/linux-5.4-ansc/board.dts`
- Quick Config：`device/config/chips/v821/configs/perf2b/quick_config.json`
- MDIO sysfs 实现：`bsp/drivers/gmac/sunxi-mdio.c`
- V821 pinctrl 定义：`bsp/drivers/pinctrl/pinctrl-sun300iw1.c`
