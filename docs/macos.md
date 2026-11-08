# Akali360 运行 macOS 15

调查日期：2026-11-07。机器是内置 eMMC 上的 Kubuntu 26.10，固件 `MrChromebox-2509.1`（2025-10-13）。这次只对照硬件和当时还能维护的开源驱动，没有安装 macOS，没有抹盘，没有刷固件。

## 结论

可以拿 USB 盘试 macOS 15 Sequoia，不能把它当成这台机器的原生系统。

i5-8350U 和 UHD 620 属于苹果在 Sequoia 里拿掉的 Kaby Lake 一代。2026 年 11 月的 OpenCore Legacy Patcher 仍能把这代核显的 Metal 补回去，所以图形加速有一条现成的路，但每次系统更新都要重新打 root patch。无线有 2026 年还在发布的 `AirportItlwm` 分支，7265 在它的硬件表里，能做系统里的 Wi-Fi。这个分支写明不支持 AWDL / AirDrop。上游驱动到 Sonoma 为止，也只做到 Handoff 和通用剪贴板。

内置扬声器、耳机和麦是 I2S 上的 DA7219、MAX98357A、DMIC，没有 macOS 驱动。内置盘是 Intel eMMC（`8086:9d2b`），不是 NVMe。macOS 没有这块控制器的驱动，抹掉那 58GB 也不会变成可用的系统盘。microSD 槽是另一回事：插卡之后它是一颗 Genesys USB 读卡器，macOS 和这份 UEFI 都按普通 U 盘处理。Kubuntu 继续留在 eMMC 上。

400 MHz、风扇和睡眠这三件，Linux 上的修复都不能原样搬进 macOS，但也不是三件都没有别的路。功耗墙在 CPU 寄存器里，风扇的日常曲线在 EC 里，只有睡眠的 S3 是这台板自己的故障。分开写在最后一节。

## 这台机器

| 项目 | 值 |
| --- | --- |
| 机型 | Acer Chromebook Spin 13，板名 Akali360，底板 nami |
| CPU | i5-8350U，4 核 8 线程，最高 3.6 GHz |
| 核显 | UHD 620，`8086:5917`，eDP 2256×1504 |
| 内存 | 7.6 GiB |
| 内置盘 | eMMC 58.2GB，PCI `8086:9d2b`（`\_SB_.PCI0.EMMC`） |
| 无线 | Intel Dual Band Wireless-AC 7265，`8086:095a`，子系统 `8086:9010` |
| 蓝牙 | USB `8087:0a2a`，接在 xHCI 端口 5 |
| 音频 | I2C 上的 DA7219（`I2C3.DLG7`）和 MAX98357A（`I2C3.MAXM`），另有 DMIC；HDA 控制器 `8086:9d71` 只挂着 HDMI |
| 键盘 | PS/2，`AT Translated Set 2 keyboard` |
| 触摸板 | `ELAN0000`，`\_SB_.PCI0.I2C1.D015` |
| 触摸屏 | `ELAN0001`，`\_SB_.PCI0.I2C0.D010` |
| 笔 | Wacom `WCOM005C`，`2D1F:0066`，`\_SB_.PCI0.I2C2.H009` |
| 摄像头 | USB UVC，Chicony `04f2:b667` |
| 电池 | Panasonic `AP15O5L`，挂在 Chrome EC 上 |
| 固件 | `MrChromebox-2509.1`，EC 仍是出厂 `nami_v1.1.8959-e1bcde2e3` |

PCI `00:1e` 上只有 eMMC（`8086:9d2b`），没有 Intel 的 SD function `8086:9d2d`。microSD 槽不走那块 PCI 设备。2026-11-07 把卡插上之后，USB 3 口 `\_SB_.PCI0.XHCI.RHUB.SS04` 上出现 Genesys Logic `05e3:0747`，Linux 把它认成 232.2GB 的 `sda`。同一颗芯片在 nami 底板上就是内置 microSD 读卡器。芯片在拔卡后会从 USB 上断开，所以空槽时 `lsusb` 里没有它。卡必须在按电源之前就插着，固件扫描 USB 时才看得到。

## macOS 15 本身

截至 2026-11-03，OpenCore Legacy Patcher 的说明仍把 Sequoia 列为支持范围。目录里的最新安装包是 15.8.2（`24H232`，2026-10-26），下载约 15.7GB。稳定版补丁器是 2.5.1；3.0.0 在 2026-10-28 发布。苹果原生能装 Sequoia 的 Intel 机型从 2018 年的 Coffee Lake MacBook Pro、2018 年 Mac mini 和 2019 年 iMac 起算。2017 年的 Kaby Lake MacBook Pro 不在里面。i5-8350U 是 Kaby Lake-R，核显设备号 `5917`，和那批被拿掉的机器是同一代图形。

Dortania 的 Kaby Lake 笔记本页在 2026-03-15 还写着：Kaby Lake-R 的 UHD 620 用 `AAPL,ig-platform-id` `0000C087`，并把 `device-id` 伪装成 `16590000`。这一步只解决帧缓冲。Sequoia 里已经没有这代核显的驱动，加速要靠 OCLP 给 Kaby Lake 补回的 Metal root patch。root patch 会改系统卷，SIP 要放低，系统一更新补丁就没了，得再打一次。iPhone 镜像和 Apple Intelligence 依赖 T2 或 Apple 芯片，这条路上没有。

SMBIOS 用仍被 Sequoia 接受的型号时，要加 `RestrictEvents` 跳过 board-id 检查。用 Kaby Lake 自己的 `MacBookPro14,1` 则会被系统直接拒绝。两种都还没在这台机器上试过。

## 各部分能不能动

| 部分 | 现成驱动 | 判断 |
| --- | --- | --- |
| 启动 | 已经是 MrChromebox 全量 UEFI | OpenCore 从 USB 启动，不需要再刷固件 |
| CPU | OpenCore 的 Kaby Lake `XCPM` | 能跑。15W 的墙在 package 寄存器里，见最后一节。只换系统不会把 Linux 里写成的 20W 带过去 |
| 核显 | WhateverGreen，加上 OCLP 的 Kaby Lake Metal root patch | 先能出画面，加速要等 root patch。2256×1504 不是 Mac 的标准分辨率，HiDPI 要另外指定 |
| USB / USB-C | 原生 xHCI `8086:9d2f` | 端口要做成内置映射。右侧 USB-C 的显示输出要单独对 `con` 口，这次没测 |
| Wi-Fi | `laobamac/itlwm` 的 `AirportItlwm-Sequoia` | 7265 在上游硬件表的 7000 系列里。这个分支测过 15.8，2026-10-11 还有 `v2.4.0-alpha`。用系统自己的 Wi-Fi 菜单，不必再打 OCLP 的 Wi-Fi root patch |
| AirDrop | 没有对应实现 | 见下一节 |
| 蓝牙 | `OpenIntelWireless/IntelBluetoothFirmware` | 上游 2024-06 为 Sequoia 改过，2026-01-15 把版本抬到 Tahoe。7265 的 Stone Peak 固件在仓库里。2026-08 仍有人在 15.5 上让同一颗 7265 失败。USB 口必须映射成内置 |
| 键盘 | `VoodooPS2`，Chromebook 上用的是 1Revenger1 的分支 | PS/2 键盘能进系统。顶排键和亮度要自己的映射，Drallion 那份指南走的就是这条 |
| 触摸板 | `VoodooI2C` + `VoodooI2CELAN` | `ELAN0000` 是这个驱动写明支持的 Chromebook 触摸板。还要 GPIO 和 `SSDT-XOSI`，中断脚没在这次对过 |
| 触摸屏 / 笔 | `VoodooI2CHID` | `ELAN0001` 和 `WCOM005C` 都是 I2C HID。Drallion 上另一种 Wacom 触摸屏能用这个驱动。这两个 ID 没有现成记录 |
| 摄像头 | 系统自带 UVC | `04f2:b667` 在 Linux 上已经是普通 USB 摄像头。端口映射成内置之后，大概率直接可用 |
| 扬声器、耳机、麦 | 没有 | AppleALC 只认 HDA codec。这三路在 Intel AVS 的 I2S 上 |
| HDMI 声音 | AppleALC 可能只覆盖 HDMI | HDA 控制器在，模拟 codec 不在。只对显示器上的声音有机会 |
| 电池 | `VirtualSMC` + `SMCBatteryManager`，读数过长时用 `ECEnabler` | 电池挂在 Chrome EC 上。EC 的字段多半超过 8 位，`ECEnabler` 就是给这种情况的。电量未必第一次就能读准 |
| 风扇 | EC 自己的曲线，不需要驱动 | 日常转速还在。`akali_fan` 的手动曲线和睡眠停转没有现成的 macOS kext |
| 睡眠 | `\_SB.LPS0` 打开 Deep Idle | S3 仍然是坏的。macOS 15 有一条和 Linux `s2idle` 同类的入口，见最后一节 |
| 内置 eMMC | 没有 | `8086:9d2b` |
| microSD 槽 | 系统自带的 USB 大容量存储 | Genesys `05e3:0747`，接在 `SS04`，USB 3.0 5 Gbps。Bulk-Only 传输。macOS 把它当外置盘。OpenCore 的 USB 映射必须留下 `SS04`，否则进系统后这张卡会消失 |

## Wi-Fi 和 AirDrop

要分两套驱动，不能同时加载。

`itlwm.kext` 加 HeliPort 把无线做成以太网。Sequoia 早期测试里这套能连上。它不进系统的 Wi-Fi 菜单，也没有 AirDrop。上游稳定版停在 `v2.3.0`（2024-06-09），最高写到 Sonoma。

`AirportItlwm.kext` 走系统的 Wi-Fi 栈。上游 FAQ 写明：连续互通里只有 Handoff 和通用剪贴板，AirDrop 不在其中；Monterey 以后 Handoff 还是单向的。Sequoia 把 Wi-Fi 栈换成了用户态，旧的 `AirportItlwm` 因此停在 Sonoma。2024 年有人用 OCLP 的 Wi-Fi root patch 去加载 Ventura 版 `AirportItlwm`，报告过单向 AirDrop，但增量更新会被 root patch 弄坏。

2026 年还在更新的是 `laobamac/itlwm`。它的 `AirportItlwm-Sequoia` 在 15.2 以后走原生 Wi-Fi，作者写明测过 15.8，并且 Sequoia 和 Tahoe 要各用各的 kext。同一份说明把 Tahoe 的限制也加在 Sequoia 上：WPA3-only、强制 PMF、AWDL / AirDrop、MLO 都不支持。7265 没有 802.11ax，`itlwm_he` 跟它无关。这是目前该用的无线驱动。它解决的是能上网，不是 AirDrop。

蓝牙固件用 `OpenIntelWireless/IntelBluetoothFirmware`，再加 `BlueToolFixup`。`IntelBTPatcher` 在 Sequoia 上有人可以不加载，也有人加载后开机变慢。先只放固件和 `BlueToolFixup`。AirDrop 即使用上蓝牙，没有 AWDL 也不会因此出现。

## 磁盘放哪里

内置盘 `mmcblk0` 是 58.2GB，EFI 300MB，系统分区 57.9GB。调查时 Kubuntu 用了 11GB，剩 44GB。Sequoia 的安装包本身约 15.7GB，OCLP 要求做安装盘的 U 盘至少 32GB。装完再留 root patch 和后续更新的空间，58GB 抹掉也偏紧。

更根本的问题是控制器。这块 eMMC 走 Intel `sdhci-pci`。macOS 没有对应的 kext，OpenCore 也看不到一块它不认识的盘。抹掉只会使现在的系统消失。

这张 256GB 卡插在槽里时是 `/dev/sda`，232.2GB。原来的 Switch 分区已经清掉，现在只有一个 512MB 的 EFI，卷标 `AKALI-ESP`，其余还没划。读卡器是标准 USB Mass Storage（接口类 `08/06/50`）。安全启动是关的。卡要在开机前插好。

2026-11-07 用一次性启动项从这张卡加载了 `\EFI\akali-sd\grubx64.efi`，机器停在这个 GRUB 里。固件已经把卡上的 EFI 跑起来了。GRUB 接着去交回内置盘时失败，所以停在 shell，不是卡不能启动。强制重启之后回到 Kubuntu，因为那次启动项只生效一次。

读卡器芯片 GL3224 的卡侧是 UHS-I，最高 SDR104。卡上的 DDR200 标记在这个槽里到不了 200 MB/s。USB 这边是 5 Gbps。

OpenCore 和以后的系统放在这张卡上。eMMC 上的 Kubuntu 和已有的 EFI 不动。macOS 会把整张卡看成外置盘。

## 和已经做完的 Linux 修复的关系

这三件都不是「macOS 完全没办法」。Linux 里的服务和内核模块不能加载进 macOS。硬件本身还在。

400 MHz 是 package 功耗墙，不是操作系统把频率锁死。CPU 同时看两份限，用更低的那份：MSR `0x610`，和 MMIO 上的另一份。Linux 的 `akali-pl1.sh` 把两份的 PL1、PL2 都写成 20W。只写其中一份时，另一份仍是 15W，频率还是会掉下去。macOS 有现成的 [VoltageShift](https://github.com/sicreative/VoltageShift)，它能写 MSR `0x610`，并且可以用 launchd 在开机时再写一次。它不写 MMIO 那一份。所以在这台机器上，只跑 VoltageShift 的 `power` 命令还不够，要补上和 Linux 相同的那次 MMIO 写入。寄存器不锁，bit 63 仍然不要设。这件事还没在 macOS 上试过。

风扇的日常曲线不靠 `akali_fan`。EC 按 Local 温度自己转，macOS 不装驱动也是这样。模块多做的两件事是手动转速，以及睡眠时在不烫的情况下停转。这两件是 EC 命令 `PWM_SET_FAN_TARGET_RPM` 版本 0 和 `THERMAL_AUTO_FAN_CTRL` 版本 0。macOS 没有现成的 kext 发这两条命令。要的话得新写一个很小的驱动，走和 Linux 一样的 LPC 主机命令。日常使用不需要它。

睡眠要分开看。离电进 S3 会掉电，醒来是冷启动；插电进 S3 能回到原会话，但 EC 不睡，风扇满转。这是固件行为，Windows 上也这样。不要刷 EC。

Linux 上能用的那次不是 EC 的 S0ix。`docs/sleep.md` 里，`s2idle` 黑屏期间 printk 时钟一直在走，CPU 整段停在 PC10，灯保持蓝色，风扇仍按 Local 曲线转，`last_resume_result` 仍是 0。日志里没有 S0ix 切换。这次开机的内核也只报告 `supports S0 S3 S4 S5`，没有把 Low Power S0 当成默认睡眠。所以要复制的是「CPU 进 PC10、EC 保持醒着」，不是给 EC 发 `HOST_SLEEP_EVENT`。那条通知有可能把 EC 推进离电时会掐电源的那条路。

macOS 没有 `/sys/power/mem_sleep`。它的对应入口是 ACPI 方法 `\_SB.LPS0`。AppleACPIPlatform 会调用它；返回非 0 时，`IOPMrootDomain` 上出现 `IOPMDeepIdleSupported`。这是 Pike R. Alpha 在 2017 年从真 Mac 的 ACPI 里对出来的，方法名就叫 LPS0。2026 年 10 月，deeveedee 在 HP EliteBook 850 G7 上确认这条调用在 macOS Sequoia 15.8.2 和 Tahoe 26.7.1 里还在。那台机器的 S3 不能用，改走这条之后，菜单睡眠、合盖、空闲都能睡，开盖和电源键能醒。过夜耗电 Sequoia 是 25.9 mAh/h，Tahoe 是 25.4 mAh/h，和他那台机器上的 Linux `s2idle`（28 mAh/h）同一档。OpenCore 1.0.8，没有 root patch。他写明 Pike 的 LPS0 只是入口，光有这个方法并不能让那台 EliteBook 进入 s2idle，其余改动还没公布。更早的 `SSDT-DeepIdle` 能进这个状态，但 CPU 常常停在 C3，电池一小时掉百分之十几；能进 C8 或 C10 时大约一小时 2% 到 4%。

在这台 Akali360 上，第一步是加一张 SSDT，先不要动 `_S3`，也不要通知 EC：

```asl
DefinitionBlock ("", "SSDT", 2, "AKALI", "LPS0", 0)
{
    Scope (\_SB)
    {
        Method (LPS0, 0, NotSerialized)
        {
            Return (One)
        }
    }
}
```

装上 macOS 之后看两件事。`ioreg -lw0 -c IOPMrootDomain | grep IOPMDeepIdle` 里要有 `IOPMDeepIdleSupported`。然后插电睡一次。会话还在、风扇没有满转，就是和 Linux 那次同一类状态。离电再试。`pmset -g log` 如果仍写着从 S3 醒来，或者离电之后变成冷启动，说明 `_S3` 还在被优先使用。那时候再让 Darwin 看不到 `_S3`，让 AppleACPIPlatform 的睡眠状态变成 `S0 S4 S5`。这一步有风险：Deep Idle 如果没接上，睡眠菜单可能不再睡眠，或者改去休眠到磁盘。先在插电时试。

`hibernatemode 25` 是 S4，整机掉电，不是 `s2idle`。这台板子的离电 S3 已经会掐电源，S4 不拿来代替这次要的路径。`pmset` 本身也选不中 Deep Idle，它只决定睡着之后要不要再转成休眠。

CPU 必须能进 PC10，否则 Deep Idle 会很耗电。Linux 上这颗 i5-8350U 在 `s2idle` 里进过 PC10。macOS 上挡住封装 C 状态的常见设备是无线网卡和 USB。EliteBook 那次能把耗电压到和 Linux 一样，用的是带省电改动的 `AirportItlwm`。这张 7265 还没有同样的结果。Jamesits 的 `S0ixEnabler.efi` 是给 Mac 上的 Windows 打开现代待机的，方向相反，这里用不上。

盖子、电源键和 USB-C 充电在 ACPI 里都有。盖子和电源键通常能用。平板模式开关 `GOOG0006` 不会让 macOS 跟着旋转。

## 安装 macOS 15

内置 eMMC 上的 Kubuntu 不动。OpenCore 不写成默认启动项，`LauncherOption` 保持 `Disabled`，`BootOrder` 里 Kubuntu 仍是第一项。microSD 继续当安装盘，也当装好之后的系统盘。固件已经能从这张卡执行 EFI 文件。卡必须在开机前插好，空槽不会出现在 USB 总线上。

恢复镜像和系统不能放在同一个分区里，但可以放在同一张卡的不同分区上。安装器跑起来之后，只把后面的空白区域做成 APFS，不要抹掉整张卡。

### 步骤

1. 在 Chromebook 的用户目录里建立 `~/akali-macos`，下载固定版本。OpenCore 1.0.8、Lilu 1.7.2、VirtualSMC 1.3.8、WhateverGreen 1.7.1、AppleALC 1.9.8、RestrictEvents 1.1.6、VoodooPS2 2.3.7、USBToolBox 1.2.0、ECEnabler 1.0.6，以及 laobamac 的 `AirportItlwm-Sequoia` v2.4.0-alpha（`7204c69`）。蓝牙固件的最新发布包仍是 2024-02 的 v2.4.0，不含 Sequoia 补丁，第一次启动不放。
2. 用 OpenCore 自带的 `macrecovery.py` 下载 Sequoia 恢复镜像。板号 `Mac-7BA5B2D9E42DDD94`，型号码 `00000000000000000`。镜像必须小于 4GB，第二分区才能用 FAT32。MrChromebox 的固件不保证能读 exFAT。
3. 编译四张 SSDT：`CP00` 的 `plugin-type`、假 EC 加 USBX、PNLF、只返回 1 的 `\_SB.LPS0`。第一次不隐藏 `_S3`，也不通知 EC。触控板的 `SSDT-XOSI` 等键盘先能用再说。
4. 从 Sample.plist 生成 `config.plist`。机型用 Sequoia 仍支持的 `MacBookPro15,2`。核显 `AAPL,ig-platform-id` 为 `0000C087`，`device-id` 伪装 `16590000`。这台 xHCI 是 `8086:9d2f`，USB 2.0 根集线器 12 口，USB 3.0 根集线器 6 口。ACPI 里有 HS01–HS10、USR1、USR2、SS01–SS06。映射按 Sunrise Point-LP 的常见编号：HS 为端口 1–10，USR 为 11–12，SS 为 13–18。HS05 蓝牙、HS07 摄像头、SS04 读卡器标成内置。这个编号是推断，卡如果在安装器里消失，先改 SS 端口号。`XhciPortLimit` 关闭。
5. 组装 `EFI/OC`。kext 顺序以 Lilu、VirtualSMC 开头。不放 `SMCBatteryManager`，避免第一次就去读 EC 电池。键盘只用 VoodooPS2 的键盘插件。OpenCore 写到 `EFI/BOOT/BOOTX64.EFI`，这样固件里已有的 USB 项能找到它。
6. 需要人工：用 sudo 给卡分区并复制文件。EFI 保持现有的 512MB `AKALI-ESP`，后面加一个 8GB 的 FAT32 放 `com.apple.recovery.boot`，其余留空。不改 `BootOrder`，不设 `BootNext`。
7. 需要人工：关机前确认卡插着，开机按 Esc，选 USB 那一项。进到恢复环境后，用磁盘工具只格式化空白区域，再安装。安装器里的网卡菜单如果是空的，用手机 USB 共享网络。

显卡加速、触控板、触控屏、手写笔、蓝牙、喇叭和耳机孔都留到系统装完。喇叭是 Intel AVS 上的 I2S，AppleALC 管不了。

### 笔记

1. 2026-11-07，包下到 Chromebook 的 `~/akali-macos/src`。`linux/macos/fetch.sh` 会按这些校验和重下。OpenCore 1.0.8 `2011e8b7…d27b`，Lilu 1.7.2 `53967d7d…ab8`，VirtualSMC 1.3.8 `2e29a8aa…e8b`，WhateverGreen 1.7.1 `1bfdd2d4…c95`，AppleALC 1.9.8 `d4d36cd2…bcb`，RestrictEvents 1.1.6 `98170dfa…ee6`，VoodooPS2 2.3.7 `d5483298…f83f`，USBToolBox 1.2.0 `c315a3a5…fe07`，ECEnabler 1.0.6 `e2114951…f0a`，AirportItlwm-Sequoia v2.4.0-alpha `7204c69` `263d35e5…a82`。ECEnabler 只是下好了，第一次启动的 EFI 里没有它。蓝牙发布包仍是 2024-02 的 v2.4.0，没有放进去。

2. `macrecovery.py` 用板号 `Mac-7BA5B2D9E42DDD94`、型号 `00000000000000000` 取到了产品 `696-28424`（目录 `082-33203`）。`BaseSystem.dmg` 884317790 字节，校验和 `7314eb401f5e84087f621b3599f0ad21ca3cdcc2685ea2da7f76806792328e20`。chunklist 校验通过，小于 4GB，可以放进 FAT32。文件在 `~/akali-macos/recovery/com.apple.recovery.boot/`。

3. 四张表的源码在 `linux/macos/ssdt/`。`iasl` 是 Ubuntu `acpica-tools` 20260408，解包在用户目录里，没有装进系统。`SSDT-PLUG` 给 `\_SB.CP00` 加 `plugin-type`。`SSDT-EC-USBX` 在 LPCB 下加一个只对 Darwin 出现的假 EC，不改原来的 `EC0_`，另外加 USBX。`SSDT-PNLF` 是背光设备。`SSDT-LPS0` 只在 Darwin 下返回 1。编译没有警告。如果 `CP00` 或 `LPS0` 已经在 DSDT 里，这张表会加载失败，OpenCore 日志里能看到。

4. `linux/macos/build-efi.py` 从 OpenCore 1.0.8 的 Sample.plist 生成配置，`ocvalidate` 1.0.8 没有报错。机型 `MacBookPro15,2`，`UpdateSMBIOSMode` 是 `Custom`。序列号由本机 `macserial` 生成，写在 `~/akali-macos/smbios.json` 和卡上的 `config.plist` 里。ROM 用的是这台机器无线网卡的地址 `dc:71:96:4f:3e:9f`。核显属性是 `0000c087` 和 `16590000`。`LauncherOption` 是 `Disabled`，`SecureBootModel` 是 `Disabled`，`ScanPolicy` 是 0，`Vault` 是 `Optional`。`XhciPortLimit` 关闭，`AppleXcpmCfgLock` 打开。启动参数是 `-v keepsyms=1 debug=0x100 -igfxvesa`，语言 `zh-Hans:252`。调试输出 `Target` 为 `0x43`。`HaltLevel` 设为 0，避免样例里的 `0x80000000` 在任何错误日志处直接死循环。USB 映射按前面的端口假设写进 `UTBMap.kext`，匹配 `8086:9d2f`，`port-count` 为 18。HS05、HS07、SS04 是内置。

5. EFI 在 `~/akali-macos/efi/EFI`。kext 顺序是 Lilu、VirtualSMC、WhateverGreen、AppleALC、RestrictEvents、USBToolBox、UTBMap、VoodooPS2、AirportItlwm。没有 `SMCBatteryManager`。VoodooPS2 只留了键盘插件和 `VoodooInput`，鼠标和触控板插件已去掉。AirportItlwm 限制在 Darwin 24。启用的驱动是 `OpenRuntime`、`OpenHfsPlus`、`ResetNvramEntry`。发行包里没有 Apple 的 `HfsPlus.efi`，所以用同目录里的 `OpenHfsPlus.efi`。`Ps2KeyboardDxe` 不开，固件自己已经驱动这颗 PS/2 键盘。`OpenLinuxBoot` 没开。分辨率保持固件当前模式，不切到最高 GOP 模式。`HideAuxiliary` 关掉，恢复镜像才会直接出现在选择器里。`EFI/BOOT/BOOTx64.efi` 是 OpenCore 自己的。

6. 2026-11-07 写卡完成。`sudo stage-to-sd.sh --yes` 打印了 `wrote EFI and recovery`，这一行出现之前脚本已经确认卡上有 `OpenCore.efi`、`BOOTx64.efi` 和 `BaseSystem.dmg`。事后核对：`sda1` 仍是 512MB `AKALI-ESP`，FAT UUID 还是 `9134-DF85`，没有被重新格式化。`sda2` 是新建的 8GB FAT32 `AKALI-REC`，UUID `DA92-562D`，从 513MiB 开始。内置 eMMC 仍是 Kubuntu，`/boot/efi` 挂着 `35EA-86B7`。`BootCurrent` 是 `0004`，`BootOrder` 仍是 `0004,0005,0000,0001,0002,0006`。旧的 `Boot0003 akali-sd` 还在固件里，但已经不在启动顺序中，它指向的 GRUB 路径也已经从卡上换掉。开机菜单里选 `USB: Generic USB Storage`。

7. 第一次从 USB 启动停在 `OC: Driver OpenRuntime.efi at 1 cannot be loaded - Invalid parameter!`。`at 1` 只是 Sample.plist 里 OpenRuntime 的序号。OpenCore 用内存缓冲区调用固件的 `LoadImage`，MrChromebox 即便安全启动是关的，也会用自己的镜像策略拒绝这次加载。修法是 `UEFI/Quirks/DisableSecurityPolicy`。这个开关只在 OpenCore 这一次启动里放宽策略。第二次启动已经越过 OpenRuntime，停在 `OC: Driver HfsPlus.efi at 8 cannot be found!`。发行包只有 `OpenHfsPlus.efi`。样例配置的 `HaltLevel` 是 `0x80000000`，这条错误日志会直接死循环，所以屏幕上跟着一行 `Halting on critical error`。配置已改到 `~/akali-macos/efi`，`ocvalidate` 通过。写回卡需要：

```
sudo /home/alpha/akali-macos/build/update-config.sh
```

8. 第三次启动进了选择器，`AKALI-REC` 也读完了内核集合。`wake-failure` 的 `Err(0xE)` 是没有这个 NVRAM 变量。内核日志一直走到 `AppleLockdownMode` 检查通过，再等很久也没有新行。这一屏同时有四件还没写进卡里的配置：`DevirtualiseMmio` 仍开着，Chrultrabook 说明它会弄坏 MrChromebox 的运行时服务；核显被伪装成 Kaby Lake，而 Sequoia 里已经没有对应驱动；`AirportItlwm` 会在 IOKit 启动时去初始化 7265；机型 `MacBookPro15,2` 会让系统去等一颗不存在的 T2。机器停在安装器里时改不了卡。回到 Kubuntu 后改成没有 T2 的 `Macmini8,1`，关掉那三项。网卡这次不加载，安装器里用手机 USB 共享网络。

9. 看到 `updated config` 之后再启动。卡保持插着，开机按 Esc，选 `USB: Generic USB Storage`，再选 `AKALI-REC`。读取内核集合时会停一两分钟。磁盘工具只把后面的空白做成 APFS，不要抹掉整张卡。
