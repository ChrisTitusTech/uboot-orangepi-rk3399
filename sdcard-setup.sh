#!/bin/bash
set -e

if [[ -z "$1" ]]; then
  echo "Error: no device specified. Run 'lsblk' to find your SD card and pass it as an argument."
  echo "Usage: $0 /dev/sdX"
  exit 1
fi
DEV=$1

PKGFILE=$(ls uboot-orangepi-800-*.pkg.tar.zst 2>/dev/null | head -n1)
if [[ -z "$PKGFILE" ]]; then
  echo "No uboot-orangepi-800-*.pkg.tar.zst found. Building from source..."
  CARCH=aarch64 makepkg --noconfirm --ignorearch
  PKGFILE=$(ls uboot-orangepi-800-*.pkg.tar.zst 2>/dev/null | head -n1)
  if [[ -z "$PKGFILE" ]]; then
    echo "Error: makepkg failed to produce a package."
    exit 1
  fi
fi
echo "Using package: $PKGFILE"

# Resolve to base device name (strip /dev/ and any trailing partition number)
DEVNAME=$(basename "$DEV" | sed 's/[0-9]*$//')

# Verify the device exists
if [[ ! -b "$DEV" ]]; then
  echo "Error: '$DEV' is not a block device. Run 'lsblk' to find your SD card."
  exit 1
fi

# Only allow removable devices (SD cards, USB drives)
REMOVABLE="/sys/block/${DEVNAME}/removable"
if [[ ! -f "$REMOVABLE" ]] || [[ "$(cat "$REMOVABLE")" != "1" ]]; then
  echo "Error: '$DEV' is not a removable device. Refusing to run on internal drives."
  echo "Run 'lsblk' and confirm your SD card/USB drive device name."
  exit 1
fi

# Refuse to run on any device that hosts a currently mounted filesystem from /
MOUNTED_DEVS=$(lsblk -nro PKNAME,MOUNTPOINT | awk '$2 == "/" {print $1}')
for d in $MOUNTED_DEVS; do
  if [[ "$DEVNAME" == "$d" ]]; then
    echo "Error: '$DEV' contains the root filesystem. Refusing to wipe the running system."
    exit 1
  fi
done

parted -s "$DEV" mklabel gpt
parted -s "$DEV" mkpart boot fat32 62500s 1GiB
 parted -s "$DEV" set 1 boot on
parted -s "$DEV" mkpart root ext4 1GiB 100%
mkfs.fat -F32 -n BOOT "${DEV}1"
mkfs.ext4 -L ROOT "${DEV}2"
mkdir -p /mnt/boot /mnt/root
mount "${DEV}1" /mnt/boot
mount "${DEV}2" /mnt/root
if [ ! -f ArchLinuxARM-aarch64-latest.tar.gz ]; then
  wget https://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
fi
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt/root
mv /mnt/root/boot/* /mnt/boot/
bsdtar -xf "$PKGFILE" -C /mnt/boot --strip-components=1 boot/
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${DEV}2")
sed -i "s|root=/dev/mmcblk1p2|root=PARTUUID=${ROOT_PARTUUID}|" /mnt/boot/extlinux/extlinux.conf
BOOT_UUID=$(blkid -s UUID -o value "${DEV}1")
ROOT_UUID=$(blkid -s UUID -o value "${DEV}2")
printf "UUID=%s\t/boot\tvfat\tdefaults\t0 2\nUUID=%s\t/\text4\tdefaults\t0 1\n" \
  "$BOOT_UUID" "$ROOT_UUID" >> /mnt/root/etc/fstab
dd if=/mnt/boot/idbloader.img of="$DEV" seek=64    conv=notrunc,fsync
dd if=/mnt/boot/u-boot.itb    of="$DEV" seek=16384 conv=notrunc,fsync
mkdir -p /mnt/root/home/alarm
cp "$PKGFILE" /mnt/root/home/alarm/
cp copy-to-emmc.sh /mnt/root/home/alarm/
sync
umount /mnt/boot /mnt/root
