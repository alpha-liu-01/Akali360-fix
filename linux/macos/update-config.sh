#!/bin/sh
# Copy the staged config.plist onto the microSD ESP.
# Does not partition, format, or change BootOrder.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run with sudo" >&2
	exit 1
fi
DISK=/dev/sda
props=$(udevadm info -q property "$DISK")
printf '%s\n' "$props" | grep -q '^ID_VENDOR_ID=05e3$'
printf '%s\n' "$props" | grep -q '^ID_MODEL_ID=0747$'
printf '%s\n' "$props" | grep -q 'usb-0:4:'
order=$(efibootmgr | awk '/^BootOrder:/{print $2}')
case "$order" in
0004,*) ;;
*)
	echo "BootOrder does not start with Kubuntu: $order" >&2
	exit 1
	;;
esac
src=/home/alpha/akali-macos/efi/EFI/OC/config.plist
mnt=$(mktemp -d)
cleanup() {
	umount "$mnt" 2>/dev/null || true
	rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT
mount /dev/sda1 "$mnt"
test -f "$mnt/EFI/OC/Drivers/OpenRuntime.efi"
test -f "$mnt/EFI/OC/Drivers/OpenHfsPlus.efi"
test -f "$mnt/EFI/OC/Drivers/ResetNvramEntry.efi"
test ! -e "$mnt/EFI/OC/Drivers/HfsPlus.efi"
cp "$src" "$mnt/EFI/OC/config.plist"
sync
python3 - "$mnt/EFI/OC/config.plist" << 'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    config = plistlib.load(handle)
nvram = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
enabled = [item["Path"] for item in config["UEFI"]["Drivers"] if item["Enabled"]]
assert config["Misc"]["Security"]["HaltLevel"] == 0
assert config["Misc"]["Boot"]["LauncherOption"] == "Disabled"
assert config["Misc"]["Boot"]["HideAuxiliary"] is False
assert config["UEFI"]["Quirks"]["DisableSecurityPolicy"] is True
assert config["UEFI"]["Output"]["Resolution"] == ""
assert enabled == ["OpenRuntime.efi", "OpenHfsPlus.efi", "ResetNvramEntry.efi"]
assert "-igfxvesa" in config["NVRAM"]["Add"][nvram]["boot-args"]
print("card config ok")
PY
trap - EXIT
umount "$mnt"
rmdir "$mnt"
after=$(efibootmgr | awk '/^BootOrder:/{print $2}')
if [ "$after" != "$order" ]; then
	echo "BootOrder changed from $order to $after" >&2
	exit 1
fi
echo "updated config; BootOrder still $after"
