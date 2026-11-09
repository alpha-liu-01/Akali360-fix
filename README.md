# Akali360-fix

Akali360-fix is a repository for fixing issues of Google Akali and Akali360 Chromebooks running Linux. It includes the following fixes:

- Fix for the CPU being stuck at 400 MHz under full load
- Fix for 3.5mm headphone jack
- Enabling fan curve control
- Enabling `s2idle` so that the device can be suspended correctly.

### Usage

The scripts are only tested on Kubuntu 26.10. Other Linux distros might work with or without some modifications.

```bash
cd linux && ./install-kubuntu.sh
sudo reboot now
```
