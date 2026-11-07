#!/bin/sh
if [ -w /sys/power/mem_sleep ]; then
	printf '%s\n' s2idle > /sys/power/mem_sleep
fi

for input in /sys/class/input/input*; do
	name=$(cat "$input/name" 2>/dev/null) || continue
	case $name in
	"AT Translated Set 2 keyboard"|"Elan Touchpad")
		wake="$input/device/power/wakeup"
		if [ -w "$wake" ]; then
			printf '%s\n' enabled > "$wake"
		fi
		;;
	esac
done
