# Akali360 音频

调查日期：2026-11-07。机器是内置磁盘上的 Kubuntu 26.10，内核 `7.3.0-9-generic`，PipeWire 1.6.8，WirePlumber 0.5.17。声卡由 Intel AVS 驱动分开枚举。耳机当时插在机器上。

## 结论

扬声器本身能响。默认出口是 HDMI。扬声器、耳机、HDMI 在界面上原来都叫「Built-in Audio Stereo」，所以默认那一项看起来是一个无声的未知设备。插上耳机后会出现 DA7219，但默认出口仍停在 HDMI；手动切到耳机也没有声音。

耳机无声是因为 DA7219 的播放通路默认关着。`Playback Digital Switch`、`Mixer Out FilterL DACL Switch`、`Mixer Out FilterR DACR Switch` 都是关的。这三项打开之后，`speaker-test -D hw:DA7219,0` 能向耳机送出声音。

## 现成配置

发行版已经装着 Intel 的 UCM，包是 `alsa-ucm-conf` `1.2.16.1-1ubuntu1`，目录是 `/usr/share/alsa/ucm2/Intel/avs/`。`avs_da7219` 的 `BootSequence` 会打开上面那条播放通路，并按 `Headphone Jack` 切换耳机。`avs_max98357a` 负责扬声器的 `Spk Switch`。这就是现成的第三方配置，不需要再写一套混音器状态。

UCM 的查找顺序是 `conf.d/${驱动}/${声卡长名}.conf`，然后才是 `conf.d/${驱动}/${驱动}.conf`。这台机器的 DMI 是厂商 Google、产品 Akali360、板名 Akali360、版本 1.0。声卡长名是驱动自己起的：

| 声卡 | 驱动 | 长名 | PCM |
| --- | --- | --- | --- |
| 扬声器 MAX98357A | `avs_max98357a` | AVS I2S MAX98357A | 只有 `pcm0p` |
| 耳机 DA7219 | `avs_da7219` | AVS I2S DA7219 | `pcm0p` 和 `pcm0c` |
| HDMI | `avs_hdaudio` | AVS HDMI | 三个 HDMI 设备 |

`conf.d/avs_da7219/` 里只有 `Google-Atlas-1.0.conf` 和 `Google-Coral-rev2.conf`。`conf.d/avs_max98357a/` 里只有 `Acer-Lars-1.0.conf`、`Google-Cave-1.0.conf` 和 `Google-Coral-rev2.conf`。没有按驱动名回退的文件，Akali360 的长名也对不上那几个机型。`alsaucm -c hw:DA7219` 因此失败，错误是 -2。PipeWire 退回 `stereo-fallback`，不会执行 `BootSequence`，耳机通路就一直关着。

上游 HiFi 文件写的是 `PlaybackPCM "hw:${CardId},1"`，耳机的录音也是设备 1。当前这个内核两张卡都只有设备 0。把现成文件直接链上，PipeWire 会去开一个不存在的 PCM。

ChromeOS 上的 `kblda7219max` 是 AVS 之前的那套机器驱动。这颗内核枚举出来的已经是分开的 AVS 卡，那套配置对不上。

HDMI 还会被记住。`~/.local/state/wireplumber/default-nodes` 里的 `default.configured.audio.sink` 当时指向 `alsa_output.platform-avs_hdaudio.22.auto.stereo-fallback`。这个保存值压过节点优先级，所以插上耳机也不会自己切走。

## 修复

`linux/audio/ucm/` 使用同一份 Intel `BootSequence` 和插孔开关，只把播放和录音的 PCM 改成 `hw:${CardId},0`。安装位置：

| 文件 | 作用 |
| --- | --- |
| `/usr/share/alsa/ucm2/Akali360/` | 这四份配置 |
| `conf.d/avs_da7219/avs_da7219.conf` | 指向上面的耳机配置，给长名对不上的 `avs_da7219` 用 |
| `conf.d/avs_max98357a/avs_max98357a.conf` | 同样处理扬声器 |
| `/etc/wireplumber/wireplumber.conf.d/akali-audio.conf` | 节点优先级 |

Atlas、Coral、Lars、Cave 仍然先命中自己的长名文件。多出来的是驱动名那一层回退，只在长名没有命中时使用。

WirePlumber 的 `priority.session`：

| 节点 | 优先级 |
| --- | --- |
| `alsa_output.platform-avs_da7219.*` 和对应的输入 | 2000 |
| `alsa_output.platform-avs_max98357a.*` | 1500 |
| `alsa_output.platform-avs_hdaudio.*` | 100 |

耳机的 HiFi 设备带 `JackControl "Headphone Jack"`。插着时端口可用，优先级最高，成为默认。拔掉后这个端口不可用，扬声器高于 HDMI，默认回到扬声器。安装脚本会删掉 `default.configured.audio.sink`，否则记住的 HDMI 会盖过这张表。

调查时先把同一份文件放在家目录，并用 `ALSA_CONFIG_UCM2` 指过去，这样不取得 root 也能确认耳机出声。`linux/audio/install.sh` 会删掉这层：`~/.local/share/alsa/ucm2`、`~/.config/environment.d/akali-ucm.conf`、家目录里的那份 WirePlumber 片段，以及用户会话里的 `ALSA_CONFIG_UCM2`。留下这层的话，PipeWire 不会去读 `/usr/share/alsa/ucm2`。

## 部署

只装音频时，在仓库根目录执行：

```sh
sudo sh linux/audio/install.sh
```

`linux/install-kubuntu.sh` 会连同睡眠修复、风扇桥和功耗墙一起装上这份配置。脚本自己 `cd` 到所在目录，从别的路径调用也可以。

装完后核对：

```sh
alsaucm -c hw:DA7219 dump text
alsaucm -c hw:MAX98357A dump text
wpctl status
```

耳机和扬声器的配置段应是 HiFi，`PlaybackPCM` 指向设备 0。插着耳机时，默认出口是「Built-in Audio Headphones」。扬声器是「Built-in Audio Speakers」。HDMI 仍可能显示成「Built-in Audio Stereo」，它的优先级是 100。`pipewire` 进程的环境里不应再有 `ALSA_CONFIG_UCM2`。

`alsa-ucm-conf` 自己不提供这几个文件名，升级这个包不会删掉 `/usr/share/alsa/ucm2/Akali360/`。如果以后的包新增了同名的 `conf.d/avs_da7219/avs_da7219.conf`，再跑一次安装脚本。

## 实机

耳机插着时加载这套配置之后，三路出口分开了：

| 出口 | 节点 | `priority.session` |
| --- | --- | --- |
| Built-in Audio Headphones | `alsa_output.platform-avs_da7219.21.auto.HiFi__Headphones__sink` | 2000 |
| Built-in Audio Speakers | `alsa_output.platform-avs_max98357a.20.auto.HiFi__Speaker__sink` | 1500 |
| Built-in Audio Stereo（HDMI） | `alsa_output.platform-avs_hdaudio.22.auto.stereo-fallback` | 100 |

默认是耳机。DA7219 的活动配置是 HiFi，耳机端口可用。`Headphone Jack` 为 on。向这个默认出口播放过 440 Hz，用户确认耳机有声音。拔掉耳机后应回到扬声器；写下本文时还没有在机器上拔插核对这一步。
