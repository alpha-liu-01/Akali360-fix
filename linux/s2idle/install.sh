#!/bin/sh
set -e
cd "$(dirname "$0")"

install -d /etc/systemd/sleep.conf.d /usr/local/sbin /etc/systemd/system
install -m 644 akali-s2idle.conf /etc/systemd/sleep.conf.d/akali-s2idle.conf
install -m 755 akali-s2idle.sh /usr/local/sbin/akali-s2idle.sh
install -m 644 akali-s2idle.service /etc/systemd/system/akali-s2idle.service

systemctl daemon-reload
systemctl enable --now akali-s2idle.service

printf 'mem_sleep=%s\n' "$(cat /sys/power/mem_sleep)"
for input in /sys/class/input/input*; do
	name=$(cat "$input/name" 2>/dev/null) || continue
	case $name in
	"AT Translated Set 2 keyboard"|"Elan Touchpad"|"Power Button")
		printf '%s wakeup=%s\n' "$name" "$(cat "$input/device/power/wakeup")"
		;;
	esac
done
