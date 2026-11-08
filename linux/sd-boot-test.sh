#!/bin/sh
# One-shot proof that the microSD reader can boot.
# Erases /dev/sda only when it is the Genesys 05e3:0747 256GB card.
# Writes a small EFI, boots it once, then chainloads the internal Kubuntu.
set -eu
DISK=/dev/sda
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

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart AKALI-ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
udevadm settle
sleep 1
if [ ! -b "${DISK}1" ]; then
	partx -u "$DISK"
	udevadm settle
fi
mkfs.vfat -F 32 -n AKALI-ESP "${DISK}1"
mnt=$(mktemp -d)
mount "${DISK}1" "$mnt"
cleanup() {
	umount "$mnt" 2>/dev/null || true
	rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT
grub-install --target=x86_64-efi \
	--efi-directory="$mnt" \
	--boot-directory="$mnt/boot" \
	--bootloader-id=akali-sd \
	--no-nvram \
	"$DISK"
uuid=$(blkid -s UUID -o value "${DISK}1")
cat > "$mnt/boot/grub/grub.cfg" << EOF
set timeout=2
insmod part_gpt
insmod fat
insmod search
insmod search_fs_uuid
search --no-floppy --fs-uuid --set=sd $uuid
echo 1 > (\$sd)/sdboot.ok
search --no-floppy --fs-uuid --set=int 35EA-86B7
chainloader (\$int)/EFI/ubuntu/shimx64.efi
boot
EOF
# GRUB 2.14 compresses the embedded search.fs_uuid config, so the ESP
# serial is not visible to strings. blkid already supplied it to grub-install.
efibootmgr -c -d "$DISK" -p 1 -L akali-sd -l '\EFI\akali-sd\grubx64.efi'
id=$(efibootmgr | awk '/akali-sd/{print $1; exit}' | sed 's/Boot//;s/\*//')
efibootmgr -o 0004,0005,0000,0001,0002
efibootmgr -n "$id"
echo "BootNext=$id esp=$uuid"
efibootmgr -v
sync
trap - EXIT
umount "$mnt"
rmdir "$mnt"
systemctl reboot
