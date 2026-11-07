# Akali360 睡眠调查

调查日期：2026-11-07。机器从 USB 启动 postmarketOS。后面各节是当次实验的记录；开头这一节只保留还没被实验推翻的判断。

## 结论

入手点是 **MrChromebox 全量固件和 Chrome EC**，不是某一个 Linux 发行版，也不是先写一个类似 scarlet 的看门狗喂狗程序。

这台 Akali360 当前：

- 固件是 `MrChromebox-2509.1`（2025-10-13），DMI 产品名 `Akali360`。
- Linux 同时看到 `s2idle` 和 `deep`。内核默认括号在 `deep` 上，也就是 ACPI S3。
- EC 没有被换成新的 MrChromebox EC。正在跑的仍是 ChromeOS 出厂镜像：RW `nami_v1.1.8959-e1bcde2e3`，2021-01-08，芯片 Nuvoton NPCX586G，板本 769。
- 同一机型从 2019 年到 2025 年，在 Windows 10/11、Fedora、Arch、Manjaro 上有同一对症状。MrChromebox 在 2025-12 写过：这像是 **Akali 独有，其他 nami 板复现不了**，他手上没有这台机器。对应 issue 到 2026-11 仍是“无人跟进所以关闭”，不是已修复。

对照已经做完。离电 `deep` 会立刻掉电，唤醒后是 coreboot 冷启动。插电 `deep` 能回到原会话，但 EC 不睡，风扇被顶满。`s2idle` 在插电 16 秒和离电 79 秒里都回到原会话，PC10 盖住整段黑屏，风扇没有被顶满。日常睡眠改走 `s2idle`。不刷固件。风扇曲线和 0.4 GHz 锁定另算，不在这次修复里。

## 这台机器上读到的事实

| 项目 | 值 |
| --- | --- |
| CPU | Intel Core i5-8350U（Kaby Lake-R），核显 UHD 620 |
| 内存 | 约 8 GiB |
| 无线 | Intel Wireless 7265 |
| 电池 | Panasonic `AP15O5L` |
| 内核 | `6.18.52-0-lts`（postmarketOS / Alpine） |
| `/sys/power/mem_sleep` | `s2idle [deep]` |
| `/sys/power/state` | `freeze mem disk` |
| ACPI | 有 `LPIT`，所以固件向系统广告了 S0ix；同时也有 S3 |
| EC RO / RW | `nami_v1.1.8832-d2e96839a` / `nami_v1.1.8959-e1bcde2e3`（RW，2021-01-08） |
| 已加载的相关驱动 | `cros_ec_lpcs`、`cros_ec_spi`、`cros_ec_debugfs`、`iTCO_wdt`、`tpm_tis_spi` |
| 当时电源 | 市电在线，USB-C PD 约 19.8 V，电池在充电 |

当时盖子开着、系统空闲：

- `F75303_Local` 42.9°C，`Remote1`（CPU 附近）31.9°C，`Remote2`（5V 电源附近）33.9°C，三个 fault 都是 0。
- EC 风扇 3321 RPM，fault 0。
- ACPI 那路风扇读数是 0，不能拿来判断 EC 风扇。
- `/proc/acpi/wakeup` 里 `XHCI` 在 S3 唤醒上是 enabled，`LID0` enabled，`CREC` disabled。
- 开机到采样时约 990 秒，没有自己重启。`iTCO_wdt` 已加载，但机器醒着的时候并不按固定周期复位。
- `dmesg`、debugfs、`cbmem` 需要 root。这台 postmarketOS 的 `sudo` 要密码，当时没采到内核日志。系统里没有 `ectool` 和 `cbmem`。

3321 RPM 不是“风扇坏了一直满转”。Akali 的 EC 风扇表和其他 nami 不一样：最低 2700、起转 2700、最高 5500；**只有板载 Local 传感器参与调速**（35°C 停、70°C 满）。Remote1 / Remote2 的 `temp_fan_off` 和 `temp_fan_max` 都是 0，不参与。用当时的 Local 温度算：

`(42.9 - 35) / (70 - 35) ≈ 22%`，再映射到 2700–5500，得到约 3330 RPM。和实测 3321 一致。

所以醒着的时候，EC 风扇策略是对的。睡眠时风扇吼，是睡眠过程里这个闭环被打断了，不是曲线本身算错。

## 公开记录里的同一对症状

机型是 Acer Chromebook Spin 13（CP713-1WN），coreboot 板名 akali，底板 nami。

| 来源 | 和这台机器的关系 |
| --- | --- |
| [MrChromebox/firmware#176](https://github.com/MrChromebox/firmware/issues/176)（2019 起，仍开着） | 插电风扇 100%，离电直接关机或睡下去。UEFI 和旧的 legacy BIOS 都会。 |
| [MrChromebox/firmware#742](https://github.com/MrChromebox/firmware/issues/742) | 描述和这次几乎逐字相同：插电风扇满转并且没有真正睡下去；离电能睡，唤醒时风扇满转然后重启。Windows 10/11 和 Fedora 一样。2026-11-04 因无人跟进而关，不是修好了。 |
| [MrChromebox/firmware#840](https://github.com/MrChromebox/firmware/issues/840) | 另一台 Akali360。`2408` 上 Windows 睡眠是“风扇满转，开盖重启”。升到 `2509.33` 并打开 Modern Standby 之后，睡眠好了，但 `FspMemoryInit` 变成约 20 秒。MrChromebox 认为这是 Akali 特有，不是整个 nami 家族。 |
| 同 issue 里 2025-04 的 EC 串口 | 见下一节。这是目前唯一一段能看出 EC 电源状态的日志，不是这次抓的。 |

有人在 Manjaro 上用休眠（hibernate / S4）代替睡眠，会话能恢复。那是绕开 S3，不是 S3 修好了。USB 上的 postmarketOS 现在没有把它当成可用的睡眠方案。

## 两条症状分别像什么

### 离电：睡得下去，唤醒变成重启

别人在同一机型上抓到的 EC 日志是：

1. `power state 8 = S0->S3`，随后停在 `power state 2 = S3`。
2. 大约两分钟后 `power state 7 = S3->S0`，EC 认为唤醒完成。
3. 紧接着的 port 80 是一长串 `00 02 7f …`，形态更像 coreboot 重新冷启动，而不是一条很短的 S3 resume。

这段睡眠有两分钟。EC 的睡眠失败检测默认大约 10 秒就会升级（先唤醒，再硬复位）。它如果在睡觉期间动手，EC 不会乖乖在 S3 停两分钟再做一次干净的 `S3->S0`。所以 **离电这条更像 S3 已经进去了，唤醒路径把 CPU 带进了一次新的启动**。可能的位置是 coreboot/FSP 的内存唤醒、PCH 把这次上电看成掉电，或 EC 在 `S3->S0` 时把 `RSMRST` 做成了冷复位。要确认必须看这次意外重启之后的 `cbmem -1`。成功的 S3 唤醒不会再跑一遍内存训练；失败回退成冷启动时，cbmem 里通常会留下 resume 失败的记录。

`#840` 里另一台 Akali 的冷启动卡在 `FspMemoryInit` 约 20 秒，说明这台板的内存初始化本来就和其他 nami 不一致。S3 唤醒依赖同一段内存退出路径，这是固件侧最值得盯的点。

### 插电：屏幕像睡了，风扇吼

EC 只有在离开 S0 之后才会停掉自己的风扇闭环。nami 的 `HOOK_CHIPSET_SUSPEND` 只拉背光和 USB3 电源，并不负责把风扇停转。风扇停，是因为整机进入了 S3/S0ix，EC 不再按 RPM 闭环调速。

Akali 只要还留在 S0，Local 高于 35°C，风扇就不会低于 2700 RPM。空闲时它已经在 3300 RPM 左右。睡眠时如果 EC 仍以为自己在 S0，风扇一定还在转。

更响的那一档有过实测。`#176` 的 EC 控制台在出问题的睡眠里读到：

`Actual: 0 rpm  Target: 2982 rpm  Duty: 100%  Status: frustrated  Mode: rpm`

这是 RPM 模式丢失转速反馈后的标准动作：目标还在 3000 左右，测速读数变成 0，控制器把占空比顶到 100%，并标成 frustrated。人听到的就是满转。测速线掉了、风扇供电还在，就会是这个结果。插电时部分电源轨掉下去、EC 却没进入睡眠，和这个现象相符。

插电和离电的差别，优先怀疑两件事：

- 充电器在线时 S3 根本没完成，系统停在“显示关了、EC 仍在 S0”。USB-C PD 现在是醒着的，而且 `XHCI` 的 S3 唤醒是开的。
- 离电时 S3 能完成，于是风扇停了，坏的是后面的唤醒。

Windows 上也是这一对症状，所以不能先归咎于 postmarketOS 把 `XHCI` 唤醒打开了。它仍然是第一次对照实验里要关掉的变量。

## 和 scarlet 看门狗的关系

scarlet（Acer Chromebook Tab 10，RK3399）上那种“不按时喂狗就会复位”的看门狗，和这里不是同一个故障。

x86 ChromeOS 上真正接近的机制是 EC 的 **睡眠迁移看门狗**，不是一个醒着也要周期喂的计时器：

- 内核 `cros_ec` 在睡眠前发 `EC_CMD_HOST_SLEEP_EVENT`。
- 超时字段为 0 时，EC 使用默认窗口（大约 10 秒），并盯着 `SLP_S0#` / `SLP_S3#` 这类硬件信号。
- 信号没来，EC 会唤醒；再失败就硬复位。Redrix 等更新的板子上，这会表现为睡下去大约 20–30 秒后重启。Linux 侧把 `suspend_timeout_ms` 写成 `65535`（无限）可以关掉这段检测。MrChromebox `2609.0`（2026-09-26）的 EC 更新说明里写了默认改成无限超时，用来绕开这个内核行为。

这台机器对不上这个模型的地方：

- 醒着已经超过 15 分钟，没有周期复位。Intel TCO 看门狗驱动在，但没有在 S0 里咬人。
- 上面那段 EC 日志里，S3 保持了大约两分钟。默认 10 秒的睡眠检测如果生效，不会允许这么长的 S3。
- 正在跑的 EC 是 2021 年的 nami 镜像。`2609.0` 的“无限睡眠超时”和“风扇 slam-to-max / stall 修复”都比当前固件新，而且 `2509.1` 的发布说明只给 Tiger Lake / Alder Lake 更新了 EC，没有写 nami。

所以：先用 `ectool` 读一次 hang-detect 状态，确认没有人把运行时看门狗打开。在那之前不要移植 scarlet 的喂狗服务。睡眠超时那一档只在实验证明走的是 S0ix、并且 EC 在大约 10–30 秒时复位，才值得设成无限。

## 固件版本差在哪

当前是 `2509.1`。和睡眠有关、但这台机器还没吃到的更新：

| 版本 | 和这台板可能有关的内容 |
| --- | --- |
| `2509.33`（别人的 Akali，不是这台） | 打开 Modern Standby 后 Windows 睡眠可用；同时出现很长的内存初始化。 |
| `2606.0` | coreboot 给 S0ix 增加了 EC/CREC 通知，Windows 的 EC 驱动才会跟着发 `HOST_SLEEP_EVENT`。nami 的 SMBIOS 可旋转类型有修正，和睡眠无关。 |
| `2609.0` | EC 侧：默认无限 host-sleep 超时；风扇“slam-to-max、stall、越界读”修复。发布说明没有点名 nami。刷完要再读 EC 版本。如果还是 `nami_v1.1.8959`，这段 EC 修复没有进这台板。 |

`#840` 还说明一件事：在 Akali 上关 Intel ME、清 NVRAM、Refresh+电源硬复位，都没有解释那 20 秒的 `FspMemoryInit`。刷更新之前先备份全量 ROM。不要为了试睡眠去关 ME。

## 基线结果（2026-11-07，插电）

这一步没有主动执行睡眠。当前这次启动的日志里，开机后约 166 秒（内核时钟）已经发生过一次 `deep` / S3，并且回到了同一个内核。采样时风扇 3212 RPM，Local 40.9°C，仍符合 Akali 的正常曲线，没有停在满转。内核 printk 时钟在 S3 里不走，下面 22 ms 是固件恢复耗时，不是睡眠时长。

| 项目 | 结果 |
| --- | --- |
| ACPI | `supports S0 S3 S4 S5`，表里有 `LPIT` |
| 当前选择 | `s2idle [deep]` |
| `suspend_timeout_ms` | `0`（交给 EC 默认值） |
| `last_resume_result` | `0x00000000`，EC 没有报告睡眠超时 |
| iTCO 看门狗 | `inactive`，超时 30 秒，`bootstatus=0`，`nowayout=0` |
| 这次 S3 | 内核从 `suspend entry (deep)` 走到 `Waking up from system sleep state S3`，不是重启 |
| coreboot | `prev_sleep_state 3 (S3)`，找到 OS waking vector `0x000991d0`，走 `BS_OS_RESUME`（12 ms） |
| 全局复位 | `TCO_STS` 全 0，`GBLRST_CAUSE` 全 0 |
| 内存 | LPDDR3 `MT52L512M32D2PF-10`，每通道 4096 MB，和约 8 GiB 内存一致 |
| EC | coreboot 再次确认 RW `nami_v1.1.8959`，运行镜像是 RW |
| CR50 | `cr50_v4.11_mp.62`，S3 resume 时 TPM startup 返回 0 |

唤醒源已经能从 romstage 开头的寄存器读出来：

- `pm1_sts = 0x8000`，coreboot 只解出 `WAK`。电源键、RTC、PCIe wake 状态都没有置位。`pm1_en = 0x4100` 是电源键使能加上 `PCIEXPWAK_DIS`，PM1 这条 PCIe 唤醒是关着的。
- `gpe0_sts[3] = 0x00010000`，`gpe0_en[3] = 0x00012000`。标准 GPE 的 bit 16 是 `LAN_WAK_STS`，bit 13 是 `PME_B0`。使能位和状态位的交集只有 `LAN_WAKE`。`PME_B0` 开着，但这次没有置位。
- Linux 把这个 GPE 叫 `gpe70`（十六进制；十进制 112）。没有 `gpe112` 这个文件。
- 同一阶段 coreboot 把 Chrome EC 的 WAKE mask 写成 0。这次把机器拉起来的不是 EC 主机事件。

醒着再读了一次 GPE。`gpe70` 仍然 `enabled`，计数是 0，所以这根线在 S0 里没有一直处于有效电平。`gpe6E` 计数 122，也是 `enabled`；标准 GPE 的 bit 14 是 eSPI，这是运行时 EC 事件，不是这次 S3 的唤醒源。其余看到的 GPE 要么是 `disabled`，要么是 `STS invalid`。

同一次 S3 的内核时间线：

- 166.249 进入 `deep`，166.604 同步文件系统。
- 166.993 准备进 S3，ACPI EC 停止。
- 167.015 低层恢复完成。从准备进 S3 到恢复只有大约 22 ms。
- 八个逻辑核都下线后又上来。EC 中断和事件随后解开。
- 167.052 `iwlwifi` 重新配置固件。167.194 `PM: suspend exit`。中间没有报错。

`/var/log/messages` 里没有 suspend、sleep、lid、idle 记录，这次是谁触发的还对不上。

那次恢复时 `LAN_WAKE` 的状态位是置着的，所以它仍是那一次的唤醒候选。没有墙上时钟，不能再说机器只睡了 22 ms。7265 在恢复时重配固件，和无线网卡 `WAKE#` 接到这根线相符，但不能单独定死。

`ectool` 没编过。Alpine 的 `ln` 不支持 `ln -r`。`/sys/kernel/debug/cros_ec/console_log` 的读会一直等到 EC 打出新行，`grep` 整个文件会停在那里。Ctrl+C 停掉的是这条读，机器本身没有死机。不要再直接读这个文件。

## 插电 deep，gpe70 关闭（18:06–18:08 GMT）

在机器本地终端跑了 `/home/user/akali-sleep.sh`。电源插着，`mem_sleep` 仍是 `deep`，`gpe70` 保持 `disabled`，计数一直是 0。

`echo mem > /sys/power/state` 从 18:06:54 阻塞到 18:08:21，大约 87 秒，返回 0。屏幕保持黑，电源红灯常亮，风扇满转。按电源键后回到原来的会话，没有出现 coreboot 启动画面。

醒来瞬间风扇 6221 RPM，Local 仍是 40.8°C。按 Akali 曲线，40.8°C 只对应大约 3100 RPM，曲线上限是 5500。6221 超过上限，说明占空比被顶满，不是这块板温该有的转速。三分钟后、温度不变，风扇回到 3062 RPM。

内核日志从 `suspend entry (deep)` 到 `suspend exit` 的 printk 时间只差大约 0.9 秒，其中“准备进 S3”到“低层恢复完成”是 21 ms。这和墙上的 87 秒不冲突：CPU 停在 S3 里时 printk 时钟不走，21 ms 是固件把 CPU 拉起来的耗时。AP 侧这次 S3 是成立的，电源键也能把它唤醒。

不成立的是 EC 侧。nami 的 LED PWM 带了 `PWM_CONFIG_DSLEEP`，EC 真进入深睡眠时这颗灯应当能闪。红灯常亮，加上风扇在 40.8°C 时被顶到曲线以上，说明风扇任务在这段时间里还在跑。CPU 睡了，EC 仍按醒着的状态控风扇。

`gpe70` 没有计数。Linux 没有把这次唤醒记到这根线上。

醒来后立刻读到的 EC 和 coreboot 状态：

| 项目 | 值 |
| --- | --- |
| `last_resume_result` | `0x00000000` |
| `suspend_timeout_ms` | `0` |
| 内核时间记录 | 没有 `Timekeeping suspended` 这一行，只有两次 `Waking up from system sleep state S3`（167 秒和 2526 秒） |
| `pm1_sts` / `pm1_en` / `pm1_cnt` | `8000` / `4100` / `00001400` |
| `PM1_STS` | 只有 `WAK`，没有电源键位 |
| `gpe0_sts[3]` / `gpe0_en[3]` | `00010000` / `00012000` |
| `TCO_STS` / `GBLRST_CAUSE` | 全 0 |

`last_resume_result` 的低位是 EC 看到睡眠信号变化的次数，最高位才是超时。两次 S3 之后它仍是 0：内核没有记下任何一次 EC 睡眠跳变，也没有记下超时。这和风扇、常亮红灯对得上，EC 没有报告自己进入过睡眠。`suspend_timeout_ms = 0` 表示这次发给 EC 的仍是“用默认超时”，不是无限超时。

`cbmem` 开头这 40 行和关掉 `gpe70` 之前那次恢复是同一组寄存器，包括 `GEN_PMCON`。coreboot 只看到 `WAK` 和置位的 `LAN_WAKE`，没有 `PWRBTN_STS`。这台机器的电源键接到 EC，EC 再去唤醒 PCH 时可以不留下 PCH 电源键状态位，所以这不否定按键唤醒。它说明的是：用户态把 `gpe70` 标成 `disabled` 之后，固件采样到的硬件使能位（`gpe0_en[3]` 的 bit 16）仍然是开的。sysfs 关掉的是 Linux 对这根线的计数，不是 PCH 里的唤醒使能。

87 秒是 `date` 在 `echo mem` 前后给出的墙上时间，加上黑屏、满转风扇和常亮红灯。内核没有打印它自己测量的睡眠时长。

## 离电 deep（18:19 GMT）

`/home/user/akali-battery.txt` 在 `sleep start 1794075546` 处结束，没有 `sleep end`。18:24 重新 SSH 时 uptime 只有 156 秒，充电器已经重新插上。这是一次新启动，不是回到原来的会话。

当时的状态：`ac=0`，电池放电、76%，`mem_sleep` 仍是 `deep`，`gpe70` 仍是 `disabled`。睡眠前风扇 2824 RPM，Local 35.9°C。

你看到的是：熄屏，风扇停转，红灯每秒闪一次。按电源键后灯立刻变成蓝色，风扇满转大约两三秒后回到正常，然后直接进入 coreboot 启动画面。

红灯按每秒闪、风扇停，是 EC 进入了自己的睡眠。这和插电那次相反：插电时红灯常亮、风扇在 40.8°C 被顶到 6221 RPM，但会话还在。离电时 EC 睡对了，AP 却没有从 S3 恢复，而是重新跑了 coreboot。

| | 插电 deep | 离电 deep |
| --- | --- | --- |
| EC 灯 | 红灯常亮 | 红灯每秒闪一次 |
| 睡眠中的风扇 | 满转 | 停转 |
| 唤醒 | 回到原会话 | coreboot 启动画面，新的一次启动 |
| `last_resume_result` | 两次之后仍是 0 | 进程没能活着读它 |

## 离电唤醒后的这次启动

`cbmem` 里没有 `S3 Resume`。romstage 写的是 `Normal boot`，`prev_sleep_state 0 (S0)`。

| 寄存器 | 插电那次 S3 恢复 | 离电唤醒后的这次启动 |
| --- | --- | --- |
| `pm1_sts` | `8000`（`WAK`） | `0000`（没有唤醒状态） |
| `pm1_cnt` 的 SLP_TYP | `0x1400`，类型 5，即 S3 | `0x1c00`，类型 7，即 S5 |
| `prev_sleep_state` | `3 (S3)` | `0 (S0)` |
| `GEN_PMCON` | `e0a40200 00001838` | `e0800200 00001238` |
| ME 电源事件 | `Clean Moff->Mx wake` | `Power cycle reset through Moff` |

PCH 没有把这次上电当成从 S3 醒来。睡眠类型剩在 S5，唤醒状态位是空的，管理引擎认为自己经历了一次掉电再上电，而不是干净的 S3 唤醒。coreboot 因此走普通开机，所以你会看到启动画面。

和灯、风扇放在一起：离电时 EC 自己的睡眠是成立的（红灯每秒闪、风扇停）。它在这个状态下把平台电源做成了掉电，而不是保持内存自刷新的 S3。插电时 EC 根本不进这个状态，电源轨留在 S3，CPU 就能恢复原来的会话，代价是风扇一直被顶在满转。

看门狗和全局复位原因仍然是 0。这不是 scarlet 那种喂狗问题。

限时读取 `/sys/kernel/debug/cros_ec/console_log` 得到 3133 字节。`Terminated` 是 `timeout` 在 3 秒后把它停掉，不是失败。这段记录从冷启动的 port 80 结尾开始，接着是放电中的电量（75% 降到 74%），然后是充电器重新插入：`VBUS`、20 V 的 PD 协商、`AC on`。里面没有 `power state`，也没有 S3/S5。内核这条流只包含打开之后的新行，睡眠当时的记录已经不在这 3 秒能读到的范围里。

`/home/user/ec-console` 读到的 EC 快照只有 26 行、1524 字节。内容全是充电记录，EC 时间大约 4778 到 5005 秒：电量 77% 升到 79%，以及一次 `charge_request(13200mV, 512mA)`。没有 `power state`，没有 S3/S5，没有风扇。缓冲区已经被充电打印覆盖，离电睡眠当时的记录不在了。上游 `ectool` 依赖 `libchrome`，没有继续编。

## 离电 deep，大约 5 秒（18:40 GMT）

`/home/user/akali-battery-5s.txt` 停在 `sleep start 1794076812`，没有 `sleep end`。当时 `ac=0`，电池放电、81%，Local 33.9°C，风扇 0 RPM。33.9°C 低于曲线的 35°C 停转点，所以风扇在进睡眠之前就已经停了。

现象和 18:19 那次相同：大约 5 秒后按电源键，直接进入 coreboot 启动画面，回不到原来的终端。

EC 默认的睡眠迁移检测大约是 10 秒，公开日志里离电 S3 还能停大约两分钟。5 秒比这两档都短，结果却一样。掉电发生在 EC 进入睡眠的当时，不是睡下去之后的超时，也不是看门狗。

`/home/user/ec-live-5s.txt` 里仍只有充电记录，EC 时间大约 4594 到 5153 秒，电量从 76% 记到 80%，并且写着 `to full`。这是打开 `console_log` 时吐出的旧缓冲，和进睡眠前“正在放电、81%”对不上。睡眠过程没有新的 `power state` 行落到这个文件里。用户态在冻结前记日志，看不到 EC 真正切电源的那一行。

## 离电 s2idle（18:44–18:45 GMT）

`/home/user/akali-s2idle-battery.txt` 有 `sleep end`。`echo mem` 从 `1794077084` 阻塞到 `1794077105`，大约 21 秒，返回 0。18:47 时 uptime 约 6 分钟，这次没有重新启动。`/sys/power/suspend_stats` 里 `success=1`，失败计数都是 0。这是这次启动里唯一一次成功的睡眠；前面的离电 `deep` 已经把计数清掉了。

当时 `ac=0`，电池放电、82%。脚本把 `mem_sleep` 写成 `[s2idle]`，唤醒后又写回 `[deep]`。睡眠前风扇 2908 RPM，Local 35.9°C，和曲线相符。

屏幕黑了，电源灯保持蓝色。键盘不能唤醒，电源键可以，唤醒后回到原来的终端。这 21 秒包含试键盘再按电源键的时间。

这台机器上，蓝色是开机时的灯色。离电 `deep` 里 EC 睡眠时红灯每秒闪一次；插电 `deep` 里红灯常亮。这次灯保持蓝色，EC 留在醒着的指示上，没有进入那个会掐掉平台电源的睡眠。会话因此还在。

| | 插电 deep | 离电 deep | 离电 s2idle |
| --- | --- | --- | --- |
| 灯 | 红灯常亮 | 红灯每秒闪一次 | 蓝灯保持亮 |
| 唤醒 | 原会话 | coreboot 启动画面 | 原会话，只有电源键能唤醒 |
| 时长 | 约 87 秒 | 约 5 秒也掉电 | 约 21 秒，`rc=0` |

内核日志只有两行和这次睡眠有关：

```
[  223.862321] PM: suspend entry (s2idle)
[  244.964930] PM: suspend exit
```

中间没有 `Low-level resume`。printk 时钟走了 21.10 秒，和墙上的 21 秒一致。插电 `deep` 时 CPU 停在 S3 里，printk 时钟几乎不走。这次时钟走完了整段黑屏，CPU 封装一直有电。日志里没有出现 `S0ix` 这几个字。黑屏期间的风扇转速还没有记录。

`last_resume_result` 仍是 `0x00000000`，`suspend_timeout_ms` 仍是 0。`dmesg` 里没有 `Timekeeping suspended`。

`/sys/kernel/debug/pmc_core` 不存在。ACPI 设备 `INT33A1` 在，没有驱动绑上去。这颗 `6.18.52-0-lts` 没编 `intel_pmc_core`，模块目录里也没有它。已加载的 `intel_pmc_bxt` 是另一颗芯片的驱动，只被 `iTCO_wdt` 用着。所以那四个驻留文件不会出现。

Kaby Lake 的封装 C 状态计数在 MSR。TSC 是 1.896 GHz。读数时这次启动大约 13 分钟，计数从开机累加，不是睡前睡后相减：

| MSR | 状态 | 累计 |
| --- | --- | --- |
| `0xE2` | 封装 C 状态上限 | `0x8`。Kaby Lake 用 Haswell 那张表，8 是不限制，bit 15 的锁是 0 |
| `0x3F8` | PC3 | 1.047 秒 |
| `0x3F9` | PC6 | 14.808 秒 |
| `0x3FA` | PC7 | 9.855 秒 |
| `0x630` | PC8 | 497.797 秒 |
| `0x631` | PC9 | 0 |
| `0x632` | PC10 | 20.411 秒 |

PC10 的 20.411 秒和那次 `s2idle` 的 21.10 秒对齐，差大约 0.7 秒。醒着、SSH 还连着的时间主要记在 PC8 上。PC9 一直是 0，这颗 CPU 从 PC8 直接进 PC10。固件没有把封装 C 状态封死，CPU 在这次黑屏里进过 PC10。

EC 侧仍然对不上：灯保持蓝色，`last_resume_result` 仍是 0。CPU 进了 PC10，EC 没有报告睡眠信号变化。

## 插电 s2idle（18:57–18:58 GMT）

`/home/user/akali-s2idle-ac.txt` 有 `sleep end`，返回 0。`echo mem` 从 `1794077879` 到 `1794077895`，整数秒差 16。当时插着充电器，电池充电、85%，Local 38.9°C，风扇 2997 RPM。38.9°C 按曲线大约是 3008 RPM。醒后温度和转速都没变。`mem_sleep` 写回了 `[deep]`。

两次 `pkgc` 的差值：

| 状态 | 增加 |
| --- | --- |
| PC3 | 0.009 秒 |
| PC6 | 0.061 秒 |
| PC7 | 0.001 秒 |
| PC8 | 0.188 秒 |
| PC9 | 0 |
| PC10 | 16.403 秒 |

这 16 秒黑屏几乎整段都在 PC10，进出只在 PC8 上花了 0.188 秒。离电那次的累计对齐，这次被睡前睡后的差值证实。

屏幕黑，风扇保持正常转速，没有满转。键盘和触摸板不能唤醒，电源键可以，回到原来的终端。红灯常亮，这次是充电指示。插电时红灯本来就会常亮，不能拿它判断 EC 有没有睡。风扇可以：插电 `deep` 在 40.8°C 被顶到 6221 RPM，这次 38.9°C 仍停在大约 3000 RPM。

EC 风扇闭环还在按温度转，所以 EC 没有进入会把风扇停掉的睡眠。CPU 侧已经进了 PC10。插电满转只出现在 `deep`。

离电 `s2idle` 的风扇同样是正常转速，没有满转。

## 离电 s2idle，大约 60 秒（19:01–19:03 GMT）

`/home/user/akali-s2idle-battery-60s.txt` 有 `sleep end`，返回 0。`echo mem` 从 `1794078109` 到 `1794078188`，整数秒差 79。当时 `ac=0`，电池放电、85%。`mem_sleep` 写回了 `[deep]`。

睡眠前 Local 38.9°C，风扇 3034 RPM。醒后 Local 30.9°C，风扇 0 RPM。蓝灯一直亮。风扇大约前 20 秒还在转，之后停转。键盘和触摸板不能唤醒，电源键可以，回到原来的终端。

PC10 增加 79.270 秒，PC8 增加 0.204 秒。风扇还在转的前 20 秒和停转之后，CPU 都在 PC10 里。

Akali 的风扇只看 Local，35°C 停转。38.9°C 到 35°C 是 3.9°C，整段一共降了 8.0°C。风扇转的时候降温更快，大约 20 秒掉到 35°C 后按曲线停转，剩下的时间没有风扇，再降到 30.9°C。这和蓝灯一直亮放在一起：EC 的风扇任务一直在跑，停转是温度穿过了 35°C，不是 EC 在第 20 秒进入睡眠。进入睡眠的离电 `deep` 会红灯每秒闪，并且唤醒后进 coreboot。

加热试验在 Local 从 30.9°C 走到 33.9°C 时停下，CPU 封装已经到 83°C，风扇仍是 0，没有进入睡眠。插上充电器后几秒风扇开始转。风扇曲线和 0.4 GHz 锁定以后再看。

## 修复

`linux/s2idle/` 把睡眠固定在 `s2idle`。systemd 261 的 `MemorySleepMode=s2idle` 在每次 `systemctl suspend` 前写入 `/sys/power/mem_sleep`。开机服务再写一次，并把 AT 键盘和 Elan 触摸板的 wakeup 从 `disabled` 改成 `enabled`。电源键原来就是 `enabled`。不改 EC，不刷固件。`deep` 仍留在内核里，只是不再被选中。

19:18 GMT 安装之后，`mem_sleep` 是 `[s2idle] deep`，键盘和触摸板 wakeup 都是 `enabled`。键盘可以唤醒。19:21 GMT 这次睡眠的内核记录是 `suspend entry (s2idle)` 到 `suspend exit`：启动时钟走了 40.424 秒，墙上时钟走了 40.612 秒，`CLOCK_MONOTONIC` 只走了 2.078 秒。后一个时钟在 CPU 停进空闲时是停的，所以这 40 秒里大约 38 秒不在跑系统，是睡眠，不是只关屏幕。这次启动的 `suspend_stats` 是 `success=5`。

## 下一步，按这个顺序

这些步骤是调查，不是修复。前两步不刷机。离电那一次有较大概率把 USB 系统重启掉，先把日志落到另一台机器上。

1. **基线已经拿到。** 上面的表就是这次的结果。先不要再睡眠，也先不要编 `ectool`。

2. **插电、`gpe70` 关闭的 `deep` 已经做了。** AP 能睡大约 87 秒并由电源键唤醒；EC 没有跟着睡，风扇在 40.8°C 时被顶到 6221 RPM，红灯常亮。不要读 `console_log`。

3. **离电 `deep` 是掉电开机。`s2idle` 在插电 16 秒和离电 79 秒里都回到原会话，PC10 盖住整段黑屏。** 修复是把睡眠固定在 `s2idle`，不再走 `deep`。键盘和触摸板的 wakeup 原来是 `disabled`，开机脚本会写成 `enabled`。

   | 次序 | 电源 | `/sys/power/mem_sleep` | 额外条件 | 要记录的结果 |
   | --- | --- | --- | --- | --- |
   | A | 插电 | `deep`（现状） | 不动唤醒源 | 灯是否闪，风扇 RPM，是保持睡眠还是马上亮回来 |
   | B | 插电 | `deep` | `XHCI` 唤醒关掉 | 和 A 比，插电满转是否消失 |
   | C | 插电 | `s2idle` | 同 B | Modern Standby 这条在当前 `2509.1` 上是否已经可用 |
   | D | 离电 | 在 A/C 里选一个至少能进去的 | 睡超过 60 秒再唤醒 | 唤醒是恢复会话，还是 coreboot 标志重新出现 |

   写 `mem_sleep` 用 `echo deep > /sys/power/mem_sleep` 或 `echo s2idle > /sys/power/mem_sleep`。关 `XHCI` 唤醒是 `echo XHCI > /proc/acpi/wakeup`（这个文件是切换，不是赋值）。

   判断：

   - A 灯不闪、风扇满转，B 灯闪、风扇停：插电问题是 USB 唤醒把 S3 打断了，先在系统层处理。
   - A 和 B 都是灯不闪、风扇满转，C 正常：这台固件上 S3 坏、S0ix 可用。Linux 不要再默认 `deep`。Windows 侧对应的就是打开 Modern Standby。这和 `#840` 的结果一致。
   - C 也是风扇吼或几十秒后重启：S0ix 没有真正进入。这时才试 `suspend_timeout_ms=65535`，并看 PMC 的 S0ix 驻留。不要为了试这个去黑名单 `cros_ec_lpcs`，那会同时丢掉充电、传感器和睡眠通知。
   - D 睡得住、唤醒是冷启动：问题在固件的 S3 resume。保留重启后的 `cbmem -1`。这不是用户态服务能修的。

4. **只有对照做完才动固件。**
   - 如果 C 已经好，而 D 的 S3 仍然冷启动：日常先把 Linux 固定在 `s2idle`，S3 作为固件 bug 继续跟。
   - 如果两条都不行：把全量 ROM 备份之后再考虑 `2609` 或更新。刷完立刻再读 EC 版本和 `mem_sleep`。nami 的 EC 字符串如果没变，就不要把发布说明里的 EC 修复算到这台机器上。
   - `#840` 的 20 秒内存初始化是已知风险。先确认能退回 `2509.1`。

5. **有 SuzyQ / CCD 线时补 EC 串口。** 这是 `#176` 里从 2019 年就缺的证据。睡眠前开始记，覆盖插电和离电各一次。看 `power state`、风扇的 Actual/Duty/Status，以及 `S0->S3` 之后 port 80 是短恢复还是整段冷启动。内核日志看不到 EC 有没有真的离开 S0。

## 这次没有做的事

没有人在调查开始时主动执行睡眠。开机后约 166 秒那次 S3 的触发者还没对上。没有改 `/sys/power/mem_sleep`，没有刷固件，没有改 EC。`ectool` 编译失败，没有重试。EC 控制台读取被 Ctrl+C 打断。

2026-11-07 18:02 GMT 在 SSH 里跑了一次 `rtcwake -m mem -s 45`。脚本有执行，输出在 `/tmp/akali-gpe70.txt`，所以终端是空的。`gpe70` 当时已经是 `disabled`，再写 `disable` 得到 `Invalid argument`。`rtcwake` 在设置闹钟时失败（`Invalid argument`），进程在进入睡眠之前就退出了，机器没有再次尝试 S3。Chromebook 这块 RTC 不接受 `rtcwake` 的闹钟。下一步改为直接写 `/sys/power/state`，由电源键唤醒。
