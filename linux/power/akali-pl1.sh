#!/bin/sh
# Cap Akali360 package power at 20W.
# The CPU enforces the lower of the MSR and MMIO package domains, so both
# package-0 zones are updated. PL1 alone is a 32s average: with PL2 left at
# 44W the package sprints, then the long window pays the debt back at 400 MHz.
# Setting PL2 to the same 20W removes that sprint. The MSR lock bit is not set.
set -eu
TARGET=20000000
n=0
for name in /sys/class/powercap/*/name; do
	[ -f "$name" ] || continue
	[ "$(cat "$name")" = "package-0" ] || continue
	dir=$(dirname "$name")
	[ -f "$dir/constraint_0_power_limit_uw" ] || continue
	[ -f "$dir/constraint_1_power_limit_uw" ] || continue
	pl1=$(cat "$dir/constraint_0_power_limit_uw")
	pl2=$(cat "$dir/constraint_1_power_limit_uw")
	printf '%s\n' "$TARGET" > "$dir/constraint_0_power_limit_uw"
	printf '%s\n' "$TARGET" > "$dir/constraint_1_power_limit_uw"
	pl1b=$(cat "$dir/constraint_0_power_limit_uw")
	pl2b=$(cat "$dir/constraint_1_power_limit_uw")
	printf '%s pl1 %s -> %s pl2 %s -> %s\n' "$dir" "$pl1" "$pl1b" "$pl2" "$pl2b"
	if [ "$pl1b" != "$TARGET" ] || [ "$pl2b" != "$TARGET" ]; then
		echo "package limit did not stick" >&2
		exit 1
	fi
	n=$((n + 1))
done
if [ "$n" -ne 2 ]; then
	echo "expected MSR and MMIO package-0, found $n" >&2
	exit 1
fi
