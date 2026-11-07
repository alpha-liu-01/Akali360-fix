#!/bin/sh
# akali_fan looks up the bound cros_ec_lpcs device once, inside init.
# Inserting it earlier returns ENODEV and does not retry.
i=0
while [ "$i" -lt 20 ]; do
	if modprobe akali_fan; then
		exit 0
	fi
	i=$((i + 1))
	sleep 0.25
done
echo "akali_fan: cros_ec_lpcs is not bound" >&2
exit 1
