#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y build-essential dkms "linux-headers-$(uname -r)"

SRC=/usr/src/akali-fan-1.0
rm -rf "$SRC"
mkdir -p "$SRC"
cp "$ROOT/fan/akali_fan.c" "$ROOT/fan/Makefile" "$ROOT/fan/dkms.conf" "$SRC/"
if dkms status -m akali-fan -v 1.0 2>/dev/null | grep -q .; then
	dkms remove -m akali-fan -v 1.0 --all || true
fi
dkms add -m akali-fan -v 1.0
dkms install -m akali-fan -v 1.0
# Do not use modules-load.d. That runs in parallel with udev, and akali_fan
# returns ENODEV unless cros_ec_lpcs has already bound GOOG0004.
rm -f /etc/modules-load.d/akali_fan.conf
install -m 755 "$ROOT/fan/akali-fan-load.sh" /usr/local/sbin/akali-fan-load.sh
install -m 644 "$ROOT/fan/akali-fan.service" /etc/systemd/system/akali-fan.service
systemctl daemon-reload
systemctl enable --now akali-fan.service

install -d /etc/systemd/sleep.conf.d /usr/local/sbin /etc/systemd/system
install -m 644 "$ROOT/s2idle/akali-s2idle.conf" /etc/systemd/sleep.conf.d/akali-s2idle.conf
install -m 755 "$ROOT/s2idle/akali-s2idle.sh" /usr/local/sbin/akali-s2idle.sh
install -m 644 "$ROOT/s2idle/akali-s2idle.service" /etc/systemd/system/akali-s2idle.service
systemctl daemon-reload
systemctl enable --now akali-s2idle.service

install -m 755 "$ROOT/power/akali-pl1.sh" /usr/local/sbin/akali-pl1.sh
install -m 644 "$ROOT/power/akali-pl1.service" /etc/systemd/system/akali-pl1.service
systemctl daemon-reload
systemctl enable akali-pl1.service
# enable --now does not re-run a oneshot that is already active.
systemctl restart akali-pl1.service

echo "==== boot ===="
systemctl is-enabled akali-fan.service
systemctl is-enabled akali-s2idle.service
systemctl is-enabled akali-pl1.service
echo "==== mem_sleep ===="
cat /sys/power/mem_sleep
echo "==== wakeup ===="
for input in /sys/class/input/input*; do
	name=$(cat "$input/name" 2>/dev/null) || continue
	case $name in
	"AT Translated Set 2 keyboard"|"Elan Touchpad"|"Power Button")
		printf '%s %s\n' "$name" "$(cat "$input/device/power/wakeup")"
		;;
	esac
done
echo "==== hwmon ===="
for name in /sys/class/hwmon/hwmon*/name; do
	printf '%s %s\n' "$name" "$(cat "$name")"
done
dev=$(grep -l '^akali_fan$' /sys/class/hwmon/hwmon*/name)
dir=$(dirname "$dev")
echo "device $dir"
echo "fan1_input=$(cat "$dir/fan1_input")"
echo "pwm1=$(cat "$dir/pwm1")"
echo "pwm1_enable=$(cat "$dir/pwm1_enable")"
echo "temp1=$(cat "$dir/temp1_input") $(cat "$dir/temp1_label")"
