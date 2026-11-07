#!/bin/sh
set -e
cd "$(dirname "$0")"
rel=$(uname -r)
install -d "/lib/modules/$rel/extra" /etc/modules-load.d
install -m 644 akali_fan.ko "/lib/modules/$rel/extra/akali_fan.ko"
printf '%s\n' akali_fan > /etc/modules-load.d/akali_fan.conf
depmod -a "$rel"
modprobe akali_fan
echo "---- hwmon ----"
for n in /sys/class/hwmon/hwmon*/name; do
	printf '%s %s\n' "$n" "$(cat "$n")"
done
dev=$(grep -l '^akali_fan$' /sys/class/hwmon/hwmon*/name)
dir=$(dirname "$dev")
echo "device $dir"
echo "fan1_input=$(cat "$dir/fan1_input")"
echo "fan1_min=$(cat "$dir/fan1_min")"
echo "fan1_max=$(cat "$dir/fan1_max")"
echo "pwm1=$(cat "$dir/pwm1")"
echo "pwm1_enable=$(cat "$dir/pwm1_enable")  # 2 means the EC curve"
echo "temp1=$(cat "$dir/temp1_input") $(cat "$dir/temp1_label")"
