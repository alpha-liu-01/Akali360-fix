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

能写的是 `PWM_SET_FAN_TARGET_RPM` 版本 0。它会关掉温度闭环，改成主机给定的目标转速。`THERMAL_AUTO_FAN_CTRL` 版本 0 再把闭环交还 EC。命令行程序在 `linux/fan/ec-fan.c`，它不能被 CoolerControl 调用。CoolerControl 只扫描 `/sys/class/hwmon` 里的 `pwm`。桥接模块 `linux/fan/akali_fan.c` 把这两条旧命令做成一个标准 hwmon 设备，名字是 `akali_fan`。

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

## CoolerControl

`ec-fan` 只是手动发一次命令。CoolerControl、fancontrol 不会执行它。它们要的是同一个 hwmon 设备上的：

| 文件 | 作用 |
| --- | --- |
| `fan1_input` | 当前转速 |
| `fan1_min` / `fan1_max` | 2700 / 5500 |
| `pwm1` | 可写，0 到 255 |
| `pwm1_enable` | `2` 是 EC 曲线，`1` 是手动 |
| `temp1` 到 `temp3` | Local、Remote1、Remote2 |

`pwm1` 不是占空比百分比。这颗风扇的闭环吃的是转速，而且 1 到 2699 会把占空比顶满，所以模块把滑块映射成：

| `pwm1` | 目标转速 |
| --- | --- |
| 0 | 停转 |
| 1 | 2700 RPM |
| 255 | 5500 RPM |

中间按线性插值。写入 `pwm1` 会切到手动。把 `pwm1_enable` 写成 `2` 交还 EC 曲线。卸载模块时，如果当时是手动，或者睡眠覆盖还没交还，也会把曲线交还 EC。

## 睡眠时停转

s2idle 不会让这颗 EC 进入 S3。`HOOK_CHIPSET_SUSPEND` 里那条“S3/S5 把风扇关掉”的路径不会走，所以风扇继续按 Local 曲线转。覆盖做在 `akali_fan` 的 suspend 回调里：入睡前读一次三颗 F75303，然后发一条转速命令。主机随后冻结，睡眠过程中不能再改。

| 入睡前的温度 | 睡眠期间 |
| --- | --- |
| 三颗都低于各自的限 | 目标 0，停转 |
| 任何一颗达到或超过限，或者温度读不出来 | 目标 5500 RPM |

限来自这颗 EC 的 Akali 表：Local 70°C（风扇表的满转点，halt 是 81°C），Remote1 和 Remote2 都是 59°C（EC 的 warn；这两颗不推动风扇表，所以危险时不能只把曲线交还 EC）。当前日常温度在 35°C 到 40°C，会停转。

醒来后按睡眠前的模式交还：手动就写回原来的 `pwm1`，否则 `THERMAL_AUTO_FAN_CTRL`。CoolerControl 的曲线因此还在。

转速命令会关掉 EC 的风扇闭环，而且要到醒来才恢复。睡眠中途温度再升，风扇不会自己转回来。EC 的热保护还在，Local 到 81°C 仍会让主机关机，但它不会把风扇重新打开。危险判断只发生在入睡那一次。命令失败时，温度已经超限就取消这次睡眠；温度正常就让睡眠继续，风扇保持原来的转速。

原来的 `cros_ec` hwmon 还在，它的 `fan1_input` 只读，没有 `pwm`。在 CoolerControl 里选名字是 `akali_fan` 的那一个。CPU 封装温度在 `coretemp` 上，曲线可以拿它做输入，风扇输出选 `akali_fan`。`hwmon` 的序号每次开机可能变，按名字选，不要按 `hwmonN`。

## 加载结果（postmarketOS，2026-11-07）

`sudo sh /home/user/akali-fan-bridge/install.sh` 在内核 `6.18.52-0-lts` 上加载成功。当时 `pwm1_enable` 是 2，温度闭环还在 EC 手里。

| 设备 | 名字 |
| --- | --- |
| `hwmon0` | `acpi_fan` |
| `hwmon1` | `cros_ec` |
| `hwmon2` | `coretemp` |
| `hwmon3` | `akali_fan` |

`akali_fan` 读数：

| 文件 | 值 |
| --- | --- |
| `fan1_input` | 3101 RPM |
| `fan1_min` / `fan1_max` | 2700 / 5500 |
| `pwm1` | 37 |
| `pwm1_enable` | 2 |
| `temp1` | 40850（40.9°C，`F75303_Local`） |

3101 RPM 按模块的映射是 `pwm1=37`，和读数一致。40.9°C 在 35°C 到 70°C 的曲线上大约是 3168 RPM，实测 3101，闭环仍按 Local 在转。

这台 postmarketOS 上不打算用 CoolerControl。USB 系统不再作为日常系统。`akali_fan.ko` 的 vermagic 是 `6.18.52-0-lts`，不能直接放进 Kubuntu 的内核。源码在 `linux/fan/akali_fan.c`，EC 命令和 `pwm1` 的转速映射不变。

## 加载结果（Kubuntu，2026-11-07）

内置磁盘上的 Kubuntu 26.10，内核 `7.3.0-9-generic`。CoolerControl 只能看到 `acpi_fan`（空）和 `cros_ec` 的只读 `fan1`，提示 `None of the detected fan or pump channels can be controlled`。`linux/install-kubuntu.sh` 用 DKMS 按这个内核重新编译并加载 `akali_fan`。当时 `pwm1_enable` 是 2，温度闭环还在 EC 手里。

| 设备 | 名字 |
| --- | --- |
| `hwmon1` | `acpi_fan` |
| `hwmon4` | `coretemp` |
| `hwmon8` | `cros_ec` |
| `hwmon9` | `akali_fan` |

`akali_fan` 读数：

| 文件 | 值 |
| --- | --- |
| `fan1_input` | 3212 RPM |
| `pwm1` | 47 |
| `pwm1_enable` | 2 |
| `temp1` | 40850（40.9°C，`F75303_Local`） |

3212 RPM 按 `1 + (rpm - 2700) * 254 / 2800` 是 `pwm1=47`，和读数一致。40.9°C 在曲线上大约是 3168 RPM，实测 3212，闭环仍按 Local 在转。CoolerControl 里选 `akali_fan`。`cros_ec` 仍然没有 `pwm`。这次安装时 CoolerControl 已经能对 `akali_fan` 的 `fan1` 套用曲线。

这次安装先把 `akali_fan` 写进了 `/etc/modules-load.d/akali_fan.conf`。那个服务和 udev 并行，而模块的 `init` 只查找一次已经绑定的 `cros_ec_lpcs`，找不到就返回 `ENODEV`，不会再试。EC 驱动是模块，这台机器上 `GOOG0004:00` 在开机后大约 5.5 秒才注册。所以那一行不能保证下一次开机加载成功。安装脚本已经改掉，见下一节。

## 在 Ubuntu 上部署

给另一台同样的 Akali360 用。板子上仍是 stock Chrome EC：有 `PWM_SET_FAN_TARGET_RPM` 版本 0，没有 `PWM_GET_FAN_DUTY`，主机上能看到 `cros_ec_lpcs` 绑定的 `GOOG0004`。不刷固件，也不改 EC。

在仓库根目录执行。脚本同时装上风扇桥、`linux/s2idle/` 的睡眠修复、`linux/power/` 的功耗墙，以及 `linux/audio/` 的声卡配置。

```sh
sudo sh linux/install-kubuntu.sh
```

脚本做这几件事：

- 安装 `build-essential`、`dkms` 和当前内核的 headers，按正在跑的内核编译 `akali_fan`。
- 用 DKMS 登记 `akali-fan/1.0`，`AUTOINSTALL=yes`。以后这个系统升级内核时，`/etc/kernel/postinst.d/dkms` 会按新内核再编一次。
- 安装 `akali-fan.service`，并 `enable`。它在 `systemd-udevd.service` 之后、`multi-user.target` 和 `coolercontrold.service` 之前执行 `modprobe akali_fan`。模块声明了 `softdep`，会先拉起 `cros_ec_lpcs`。绑定还没完成时，加载脚本最多再试大约 5 秒。
- 删掉 `/etc/modules-load.d/akali_fan.conf`，避免开机早期那次加载失败把 `systemd-modules-load.service` 标成失败。
- 安装并 enable `akali-s2idle.service`，把 `mem_sleep` 固定在 `s2idle`，并打开键盘和触摸板唤醒。
- 安装并重启 `akali-pl1.service`，把两份 package 功耗墙写成 20W。
- 安装 `linux/audio/` 的 UCM 和 WirePlumber 优先级，让扬声器和耳机压过 HDMI。

这台 Kubuntu 26.10 的安全启动是关闭的。DKMS 会给模块签名，但固件没有登记那把密钥，内核日志里会有 `module verification failed`，模块仍然加载，内核被标记为 tainted。安全启动开着时，这条路没有验证过；未登记的模块会被拒绝。

装完后核对：

```sh
systemctl is-enabled akali-fan.service
systemctl is-enabled akali-s2idle.service
cat /sys/power/mem_sleep
grep -l '^akali_fan$' /sys/class/hwmon/hwmon*/name
```

`akali-fan.service` 和 `akali-s2idle.service` 都应该是 `enabled`。`mem_sleep` 应该是 `[s2idle] deep`。`hwmon` 里要有名字是 `akali_fan` 的设备，并且它有可写的 `pwm1`。

开机之后模块自己的状态是 `pwm1_enable=2`，转速交还 EC 曲线。它不记住上次手动写过的转速。要让 CoolerControl 里画的曲线在开机后生效，需要 `coolercontrold.service` 也是 `enabled`。这台机器上它已经是 enabled，并且成功对 `akali_fan` 套用过曲线。服务顺序保证桥接先出现，CoolerControl 再写 `pwm`。睡眠时的停转是模块的 suspend 回调，不需要另外的服务；醒来会交还 CoolerControl 当时的手动目标，或者交还 EC 曲线。

`linux/fan/install.sh` 和 `linux/fan/pin-abi.py` 是 postmarketOS 那次用的。前者要求旁边已经有对应当前内核的 `akali_fan.ko`，后者只用于 headers 和正在跑的内核版本不一致的时候。Ubuntu 上不要走这两条。

## 命令行核对

`linux/fan/ec-fan.c` 直接对 `/dev/cros_ec` 发那两条旧命令，用来核对 EC，不给 CoolerControl 用。上面的实机记录是在 postmarketOS 上跑的，路径是 `/home/user/ec-fan`。

```sh
gcc -Wall -O2 -o ec-fan linux/fan/ec-fan.c
sudo ./ec-fan status
sudo ./ec-fan set 3500
sudo ./ec-fan auto
```

`status` 核对版本。`set` 把目标改成 3500 RPM，风扇声会离开当前曲线。`auto` 交还 EC。`GET_FAN_DUTY` 已经是 unavailable，`SET_FAN_TARGET_RPM` 的 `version_mask` 是 `0x3`。内核自带的 `cros_ec` hwmon 因此没有 `pwm`。`akali_fan` 用的是已经验证过的那两条旧命令。
