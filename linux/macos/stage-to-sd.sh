#!/bin/sh
# Copy the staged OpenCore EFI and Sequoia recovery onto the microSD.
# Leaves BootOrder and BootNext alone, and never touches the internal eMMC.
#   stage-to-sd.sh --check
#   sudo stage-to-sd.sh --yes
set -eu

DISK=/dev/sda
EFI_SRC=/home/alpha/akali-macos/efi/EFI
REC_SRC=/home/alpha/akali-macos/recovery/com.apple.recovery.boot
WRITE=0
if [ "${1:-}" = "--yes" ]; then
	WRITE=1
	if [ "$(id -u)" -ne 0 ]; then
		echo "sudo is required to partition the card" >&2
		exit 1
	fi
elif [ "${1:-}" != "--check" ]; then
	echo "use --check or --yes" >&2
	exit 1
fi

props=$(udevadm info -q property "$DISK")
printf '%s\n' "$props" | grep -q '^ID_VENDOR_ID=05e3$'
printf '%s\n' "$props" | grep -q '^ID_MODEL_ID=0747$'
printf '%s\n' "$props" | grep -q 'usb-0:4:'
bytes=$(lsblk -bndo SIZE "$DISK" | head -1)
if [ "$bytes" -lt 240000000000 ] || [ "$bytes" -gt 260000000000 ]; then
	echo "unexpected size $bytes" >&2
	exit 1
fi
if lsblk -no MOUNTPOINT "$DISK" | grep -q .; then
	echo "a partition on $DISK is mounted" >&2
	exit 1
fi
if [ -b /dev/sda2 ]; then
	echo "/dev/sda2 already exists; not repartitioning" >&2
	exit 1
fi
label=$(lsblk -no LABEL /dev/sda1 | head -1)
if [ "$label" != "AKALI-ESP" ]; then
	echo "sda1 label is '$label', expected AKALI-ESP" >&2
	exit 1
fi
esp_bytes=$(lsblk -bndo SIZE /dev/sda1)
if [ "$esp_bytes" -lt 500000000 ] || [ "$esp_bytes" -gt 560000000 ]; then
	echo "sda1 size $esp_bytes is not the 512MB ESP" >&2
	exit 1
fi
if [ ! -f "$EFI_SRC/OC/config.plist" ] || [ ! -f "$EFI_SRC/BOOT/BOOTx64.efi" ]; then
	echo "staged EFI is incomplete" >&2
	exit 1
fi
dmg="$REC_SRC/BaseSystem.dmg"
chunk="$REC_SRC/BaseSystem.chunklist"
if [ ! -f "$dmg" ] || [ ! -f "$chunk" ]; then
	echo "recovery image is missing in $REC_SRC" >&2
	exit 1
fi
dmg_bytes=$(stat -c %s "$dmg")
if [ "$dmg_bytes" -ge 4294967295 ]; then
	echo "BaseSystem.dmg is $dmg_bytes bytes, which FAT32 cannot store" >&2
	exit 1
fi
order=$(efibootmgr | awk '/^BootOrder:/{print $2}')
case "$order" in
0004,*) ;;
*)
	echo "BootOrder does not start with Kubuntu (0004): $order" >&2
	exit 1
	;;
esac
echo "card=$DISK bytes=$bytes esp=$label recovery=$dmg_bytes BootOrder=$order"

if [ "$WRITE" -eq 0 ]; then
	echo "check only, card was not modified"
	exit 0
fi

parted -s "$DISK" mkpart AKALI-REC fat32 513MiB 8705MiB
udevadm settle
sleep 1
if [ ! -b /dev/sda2 ]; then
	partx -u "$DISK"
	udevadm settle
fi
mkfs.vfat -F 32 -n AKALI-REC /dev/sda2

esp=$(mktemp -d)
rec=$(mktemp -d)
cleanup() {
	umount "$esp" 2>/dev/null || true
	umount "$rec" 2>/dev/null || true
	rmdir "$esp" "$rec" 2>/dev/null || true
}
trap cleanup EXIT
mount /dev/sda1 "$esp"
mount /dev/sda2 "$rec"
find "$esp" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$EFI_SRC" "$esp/EFI"
mkdir -p "$rec/com.apple.recovery.boot"
cp -a "$dmg" "$chunk" "$rec/com.apple.recovery.boot/"
sync
test -f "$esp/EFI/OC/OpenCore.efi"
test -f "$esp/EFI/BOOT/BOOTx64.efi"
test -f "$rec/com.apple.recovery.boot/BaseSystem.dmg"
after=$(efibootmgr | awk '/^BootOrder:/{print $2}')
if [ "$after" != "$order" ]; then
	echo "BootOrder changed from $order to $after" >&2
	exit 1
fi
echo "wrote EFI and recovery; BootOrder still $after"
efibootmgr -v
