# Akali360 风扇调速

调查日期：2026-11-07。风扇由 Chrome EC 独占。Windows 的 Fan Control 和 Linux 上走 hwmon PWM 的程序都看不到可以写的占空比，所以全部无效。主机仍然可以用 EC 的旧转速命令把闭环暂时拿过来。

## 结论

风扇的 PWM 在 Nuvoton NPCX 里，由 EC 以转速闭环驱动。主板上的 F75303 只是一颗温度传感器，接到 EC 的 I2C，主机摸不到它的寄存器。固件没有把这颗风扇做成 Super I/O 或一块可用的 ACPI 风扇。

正在跑的 EC 是 `nami_v1.1.8959-e1bcde2e3`（2021-01-08）。它实现的主机命令是：

| 命令 | 编号 | 这个镜像里的版本 |
| --- | --- | --- |
| `PWM_GET_FAN_TARGET_RPM` | `0x0020` | 0 |
| `PWM_SET_FAN_TARGET_RPM` | `0x0021` | 0 和 1 |
| `PWM_SET_FAN_DUTY` | `0x0024` | 0 和 1 |
| `PWM_GET_FAN_DUTY` | `0x0027` | 没有 |
| `THERMAL_AUTO_FAN_CTRL` | `0x0052` | 0 和 1，没有 2 |

Linux `6.18` 的 `cros_ec_hwmon` 只有在三件事同时成立时才创建 `pwm1`：`GET_FAN_DUTY` 版本 0、`SET_FAN_DUTY` 版本 1、`THERMAL_AUTO_FAN_CTRL` 版本 2。这颗 EC 缺第一件和第三件，驱动就把写接口整段藏起来。`/sys/class/hwmon/hwmon1`（名字 `cros_ec`）里因此只有只读的 `fan1_input`。Fan Control、fancontrol、CoolerControl 找的就是这个不存在的 `pwm1`，或者是一块不存在的 ITE / Nuvoton Super I/O。

能写的是 `PWM_SET_FAN_TARGET_RPM` 版本 0。它会关掉温度闭环，改成主机给定的目标转速。`THERMAL_AUTO_FAN_CTRL` 版本 0 再把闭环交还 EC。程序在 `linux/fan/ec-fan.c`。

## 这台机器上的曲线

Akali 和同家族的 nami、sona 不是同一张表。`board/nami/board.c` 在 OEM 为 Akali 时用 `fan_rpm_3`，并且只让 Local 传感器参与调速。

| 项目 | 值 |
| --- | --- |
| 模式 | `FAN_USE_RPM_MODE` |
| 最低 / 起转 | 2700 RPM |
| 最高 | 5500 RPM |
| `F75303_Local` | 35°C 停，70°C 满 |
| `F75303_Remote1`（CPU 附近） | `temp_fan_off` 和 `temp_fan_max` 都是 0，不参与 |
| `F75303_Remote2`（5V 电源附近） | 同样是 0，不参与 |

Remote1 的名字在 EC 里是 CPU 传感器，但它的风扇阈值被写成 0。CPU 很热而 Local 低于 35°C 时，风扇保持停转。这是曲线本身，不是用户态程序没有抢到控制权。

采样时 Local 46.9°C，风扇 3548 RPM。按 35°C 到 70°C、2700 到 5500 算，46.9°C 大约是 3648 RPM。ACPI 那路 `hwmon0` 的 `fan1_input` 是 0，不能用来调速，也不能用来判断风扇有没有转。

## 主机命令怎么接管

`PWM_SET_FAN_TARGET_RPM` 版本 0 的参数是一个 `uint32` 转速。EC 收到后对这颗风扇做四件事：转速非 0 就使能，关掉温度闭环，进入 RPM 模式，然后把目标设成这个数。版本 1 多一个风扇序号；这台板只有 `FAN_CH_0`，用版本 0 即可。

目标用 `0`，或 `2700` 到 `5500`。`0` 会把风扇关掉。1 到 2699 低于起转转速，RPM 闭环会把占空比往上顶，和睡眠调查里看到的满转是同一类动作。不要用这段。

`THERMAL_AUTO_FAN_CTRL` 版本 0 没有参数，把温度闭环重新打开。手动目标在这之前一直有效，温度再高也不会自己加转。进程退出、睡眠、或者不再需要手动转速时，都要执行一次恢复。

`PWM_SET_FAN_DUTY` 在这个镜像里也有，但它不会像转速命令那样先关掉温度闭环。闭环还开着时，占空比会被下一轮转速控制盖掉。调速用转速命令。

## 实机结果（2026-11-07）

`/home/user/ec-fan status` 读到的版本掩码和源码一致。`GET_FAN_DUTY` 那一行前面的 `EC command 0x8 version 1 result 3` 是查询版本时 EC 返回的 `EC_RES_INVALID_PARAM`，表示没有这条命令。

| 命令 | `version_mask` |
| --- | --- |
| `GET_FAN_TARGET_RPM` | `0x1`（版本 0） |
| `SET_FAN_TARGET_RPM` | `0x3`（版本 0 和 1） |
| `SET_FAN_DUTY` | `0x3`（版本 0 和 1） |
| `GET_FAN_DUTY` | 不存在 |
| `THERMAL_AUTO_FAN_CTRL` | `0x3`（版本 0 和 1） |

当时还在温度闭环里：目标 3293 RPM，实测 3332 RPM。

随后执行 `set 3500`、`set 5500`、再 `set 3500`，三条都被 EC 接受。风扇跟着离开了原来的曲线。最后 `auto` 返回 `thermal curve restored`，温度闭环交还 EC。

## 用法

在 Chromebook 上编译一次：

```sh
gcc -Wall -O2 -o /home/user/ec-fan /home/user/ec-fan.c
```

只读，核对这颗 EC 实际宣布的版本：

```sh
sudo /home/user/ec-fan status
```

把目标改成 3500 RPM。风扇声会离开当前曲线：

```sh
sudo /home/user/ec-fan set 3500
```

交还 EC：

```sh
sudo /home/user/ec-fan auto
```

上面的实机记录里，`GET_FAN_DUTY` 已经是 unavailable，`SET_FAN_TARGET_RPM` 的 `version_mask` 是 `0x3`。Linux 的 hwmon 写接口不会出现，而这颗 EC 接受转速命令。
