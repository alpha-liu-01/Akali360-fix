# Akali360 满载锁在 400 MHz

调查日期：2026-11-07。机器是内置磁盘上的 Kubuntu 26.10，内核 `7.3.0-9-generic`，CPU 是 i5-8350U。Windows 上用 ThrottleStop 把 package 功耗锁在 20W 之后，这个问题消失。

## 结论

满载大约 17 秒后，八个核从 2.9 GHz 一档档降到 400 MHz，然后停在 400 MHz 附近。整段时间里 package 的长期功耗墙一直是 15W，短期墙一直是 44W。封装温度停在 60°C 到 66°C。`core_throttle_count` 和 `package_throttle_count` 前后都是 0。

i5-8350U 的标称 TDP 是 15W，基频 1.7 GHz，单核最高 3.6 GHz。八个线程一起跑，功耗超过 15W。CPU 用大约 32 秒的长期窗口把平均功耗往 15W 拉，HWP 就把频率往下送。`intel_pstate` 允许的最低频率是 400 MHz（`min_perf_pct` 是 11，3600 MHz 的 11%）。窗口还没走完，频率已经穿过基频，落到这个地板上，之后只在 400 MHz 到 500 MHz 之间晃。

20W 比这次这种整数满载在可用频率上的功耗高，长期墙不再把频率送到 400 MHz。ThrottleStop 锁的就是这个 package 墙。

Package 限有两份，CPU 用其中更低的那份：

| 来源 | sysfs | 长期 PL1 | PL1 时间窗 | 短期 PL2 | PL2 时间窗 |
| --- | --- | --- | --- | --- | --- |
| MSR | `intel-rapl:0` | 15W | 31.98 s | 44W | 976 µs |
| MMIO | `intel-rapl-mmio:0` | 15W | 31.98 s | 44W | 976 µs |

两份现在一样。只抬其中一份，另一份仍是 15W，频率还会掉下去。`constraint_0_max_power_uw` 也是 15W，所以从 sysfs 把 PL1 写成 20W 可能被驱动拒绝。ThrottleStop 是直接写 MSR，能写成 20W。

还有一个 `psys` 域（`intel-rapl:1`），长期限也是 15W，但是 `enabled` 为 0，这次没有参与。

## 满载记录

八个 Python 整数循环，大约 22 秒。采样的是 `scaling_cur_freq`。PL1 每一秒都是 15000 mW。

| 时刻 | 全核频率 | 封装温度 |
| --- | --- | --- |
| 1 s | 2.9 GHz | 60°C |
| 5 s | 1.7 GHz | 56°C |
| 8 s | 1.3 GHz | 57°C |
| 10 s | 0.9 GHz | 61°C |
| 18 s | 400 MHz | 65°C |
| 22 s | 400 MHz 到 480 MHz | 65°C |

Local（`TSR0`）停在 37°C 左右，没有碰到它 75°C 的 passive 点。风扇曲线因此也不会因为这次负载加转。封装温度离 `B0D4` 的 passive 点 98°C 还远。PROCHOT 计数没有增加。

`intel_pstate` 是 active，`no_turbo` 是 0，`max_perf_pct` 是 100，调节器是 `powersave`，EPP 是 `balance_performance`。操作系统没有把最高频率限在 400 MHz。

## 和另外几个机制的关系

PROCHOT 计数在这次满载前后都是 0，温度也只有 66°C。频率是十几秒里一档档下来的，不是一下子钉死。BD PROCHOT 会立刻把倍频打到最低，并让这些计数增加。这次的曲线对不上。

`thermald` 在运行，用的是自适应模式和它生成的 `/var/run/thermald/thermal-conf.xml.auto`。那份配置来自 ACPI `_TRT`，四路温度的门限写成了 `*`，启动日志是 `Invalid integer value: '*'`。这次满载中 PL1 没有被改写，仍是 15W。当前这个 400 MHz 是 15W 那道墙本身造成的。

`TSR0`、`TSR1` 上有两档 passive 温度是 `-274000`（0 K）。内核把这个值当成无效 trip，不拿它做门限。真正会拉低功耗的 passive 点在 Local 75°C、封装 98°C。这次都没到。

把 `scaling_min_freq` 或 `min_perf_pct` 调高，改变不了这道墙。功耗仍要回到 15W，CPU 还是会把频率往下压，只是操作系统和墙对着干。

## 修复

`linux/power/akali-pl1.sh` 把名字是 `package-0` 的两份域（MSR 和 MMIO）的 PL1 和 PL2 都写成 20000000。sysfs 上的 `constraint_0_max_power_uw` 读的是标称 TDP，不是写入上限，所以 20W 走驱动写进去，不用直接 `wrmsr`。时间窗和 MSR `0x610` 的 bit 63 不动。

`akali-pl1.service` 是 oneshot，`WantedBy=multi-user.target`，`After=thermald.service`。这台机器上它是 `enabled`，`/etc/systemd/system/multi-user.target.wants/akali-pl1.service` 指向这个单元，`thermald.service` 也是 `enabled`。每次开机进 multi-user 时，thermald 起来之后脚本会再把两道墙写成 20W。这次改到 20W 之后还没有重启，开机那一次还没出现在日志里。不置锁定位。如果以后有人把 20W 写回去，再考虑 bit 63。Local 到 81°C 时 EC 仍会让主机关机，CPU 自己的温度墙还在。

只把 PL1 写成 20W、PL2 留在 44W 时，修复没有成立。服务是 `enabled`，两份 PL1 也确实是 20W，满载中没有被写回 15W。八线程再跑 50 秒，频率在 400 MHz 和 3.3 GHz 之间来回跳：2 秒 2.3 GHz，6 秒 900 MHz，10 秒 3.3 GHz，18 秒 400 MHz，20 秒又是 3.3 GHz，38 秒再次 400 MHz。封装温度在 3.3 GHz 那一下到了 95°C。PL1 是大约 32 秒的平均。PL2 仍允许短时间跑到远高于 20W 的频率，多出来的功耗要靠后面的 400 MHz 补回平均。所以两份域的 PL2 也写成 20W，package 不再有那一段冲高。`systemctl restart akali-pl1.service` 之后，MSR 和 MMIO 的 PL1、PL2 都是 20W。

八线程再跑 32 秒。两份墙每一拍都是 20W。全核停在 2.64 GHz 到 2.74 GHz，没有再出现 400 MHz。封装温度从 65°C 走到 83°C，Local 从 33°C 走到 37°C。PROCHOT 计数没有增加。Local 仍低于风扇曲线的起转点，所以这段负载不会把风扇拉高。

两个安装脚本都会 `enable` 这个服务，然后 `restart`。`enable --now` 不会重跑一个已经 active 的 oneshot，所以重复安装必须用 `restart`，否则新脚本拷上去了也不会执行。只装功耗修复时，在仓库里执行：

```sh
sudo sh linux/power/install.sh
```

`linux/install-kubuntu.sh` 会连同睡眠修复和风扇桥一起装上这个服务。脚本自己 `cd` 到所在目录，从别的路径调用也可以。

20W 是这台机器在 Windows 上已经用过的值，不超过它。这台板的风扇只看 Local。CPU 已经热而 Local 还停在 40°C 以下时，风扇不会加转。把墙抬得比 20W 更高，封装温度会先上去。PL2 时间窗仍是 976 µs，这次不改它。3.3 GHz 能持续好几秒，说明 44W 的短期墙并没有挡住这段冲高。
