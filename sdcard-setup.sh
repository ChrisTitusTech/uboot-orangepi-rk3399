#!/bin/bash

parted -s /dev/sdX mklabel gpt
parted -s /dev/sdX mkpart boot fat32 62500s 320MiB
parted -s /dev/sdX set 1 boot on
parted -s /dev/sdX mkpart root ext4 320MiB 100%
mkfs.fat -F32 -n BOOT /dev/sdX1
mkfs.ext4 -L ROOT /dev/sdX2
mkdir -p /mnt/boot /mnt/root
mount /dev/sdX1 /mnt/boot
mount /dev/sdX2 /mnt/root
wget https://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /mnt/root --exclude='./boot/dtbs'
mv /mnt/root/boot/* /mnt/boot/
bsdtar -xf uboot-orangepi-800-*.pkg.tar.zst -C /mnt/boot --strip-components=1 /mnt/boot/
ROOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/sdX2)
sed -i "s|root=/dev/mmcblk1p2|root=PARTUUID=${ROOT_PARTUUID}|" /mnt/boot/extlinux/extlinux.conf
BOOT_UUID=$(blkid -s UUID -o value /dev/sdX1)
ROOT_UUID=$(blkid -s UUID -o value /dev/sdX2)
printf "UUID=%s\t/boot\tvfat\tdefaults\t0 2\nUUID=%s\t/\text4\tdefaults\t0 1\n" \
  "$BOOT_UUID" "$ROOT_UUID" >> /mnt/root/etc/fstab
dd if=/mnt/boot/idbloader.img of=/dev/sdX seek=64    conv=notrunc,fsync
dd if=/mnt/boot/u-boot.itb    of=/dev/sdX seek=16384 conv=notrunc,fsync
mkdir -p /mnt/root/home/alarm
cp uboot-orangepi-800-*.pkg.tar.zst /mnt/root/home/alarm/
sync
umount /mnt/boot /mnt/root
