# uboot-orangepi-800

U-Boot 2022.04 bootloader package for the **Orange Pi 800** (Rockchip RK3399). Pre-built binaries sourced from Manjaro ARM 22.07.

This package provides everything needed to boot: the bootloader images, a baseline `extlinux.conf`, and the `rk3399-orangepi-800.dtb` device tree (not included in the stock `linux-aarch64` package).

---

## Requirements

- An SD card (8GB or larger recommended)
- A host machine running Linux
- `parted`, `mkfs.fat`, `mkfs.ext4`, `bsdtar` (`libarchive`), `dd`, `blkid`
- The `uboot-orangepi-800` package built locally (see below)

---

## Build the package

No cross-compiler needed — ships pre-built binaries:

```bash
git clone https://github.com/ChrisTitusTech/uboot-orangepi-rk3399
cd uboot-orangepi-rk3399
makepkg -s
```

This produces `uboot-orangepi-800-2022.04-1-aarch64.pkg.tar.zst`. Keep it in the current directory for the steps below.

---

## Install Arch Linux ARM on an SD Card

Replace **`sdX`** with your SD card device (e.g. `sdb`). Run all commands as **root**.

### Step 1 — Partition the SD card

> The boot partition must start at sector **62500** (~30 MB from the start) to leave room for the U-Boot images written directly to the raw device.

```bash
parted -s /dev/sdX mklabel gpt
parted -s /dev/sdX mkpart boot fat32 62500s 320MiB
parted -s /dev/sdX set 1 boot on
parted -s /dev/sdX mkpart root ext4 320MiB 100%
```

### Step 2 — Format and mount

```bash
mkfs.fat -F32 -n BOOT /dev/sdX1
mkfs.ext4 -L ROOT /dev/sdX2
mkdir -p boot root
mount /dev/sdX1 boot
mount /dev/sdX2 root
```

### Step 3 — Extract the Arch Linux ARM root filesystem

```bash
wget https://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C root
mv root/boot/* boot/
```

### Step 4 — Install bootloader files and configure boot

Extract the package onto the boot partition (installs `idbloader.img`, `u-boot.itb`, DTB, and `extlinux.conf`):

```bash
bsdtar -xf uboot-orangepi-800-*.pkg.tar.zst -C boot --strip-components=1 boot/
```

Patch `extlinux.conf` with the real root `PARTUUID`:

```bash
ROOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/sdX2)
sed -i "s|root=/dev/mmcblk1p2|root=PARTUUID=${ROOT_PARTUUID}|" boot/extlinux/extlinux.conf
```

Set up `/etc/fstab`:

```bash
BOOT_UUID=$(blkid -s UUID -o value /dev/sdX1)
ROOT_UUID=$(blkid -s UUID -o value /dev/sdX2)
printf "UUID=%s\t/boot\tvfat\tdefaults\t0 2\nUUID=%s\t/\text4\tdefaults\t0 1\n" \
  "$BOOT_UUID" "$ROOT_UUID" >> root/etc/fstab
```

### Step 5 — Flash U-Boot to the SD card

```bash
dd if=boot/idbloader.img of=/dev/sdX seek=64    conv=notrunc,fsync
dd if=boot/u-boot.itb    of=/dev/sdX seek=16384 conv=notrunc,fsync
```

### Step 6 — Copy package and unmount

```bash
cp uboot-orangepi-800-*.pkg.tar.zst root/home/alarm/
sync
umount boot root
```

---

## First Boot

1. Insert the SD card into the Orange Pi 800.
2. Connect an Ethernet cable.
3. Apply 5V USB-C power.

U-Boot finds `extlinux/extlinux.conf` on the boot partition and loads the kernel automatically.

Log in via SSH (use your router's DHCP table to find the IP) or serial console (**ttyS2, 1500000 baud, 8N1**):

| Account | Username | Password |
|---|---|---|
| User | `alarm` | `alarm` |
| Root | `root` | `root` |

---

## Post-Boot Setup

Initialize pacman and register the package so future upgrades reflash U-Boot automatically:

```bash
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu
pacman -U /home/alarm/uboot-orangepi-800-*.pkg.tar.zst
```

The `.install` hook will offer to reflash U-Boot to `/dev/mmcblk1` on install and upgrade.

---

## Notes on Hardware Support

The bundled `rk3399-orangepi-800.dtb` is sourced from Manjaro ARM 22.07 and is sufficient to boot the system with Ethernet. However, OPi 800-specific hardware (keyboard controller, UniSOC WiFi/BT) requires the OrangePi vendor kernel.

No AUR package exists for the vendor kernel. If you need full hardware support, you must build it manually from the OrangePi vendor kernel source:

- Repository: [orangepi-xunlong/linux-orangepi](https://github.com/orangepi-xunlong/linux-orangepi)
- Branch: `orange-pi-5.10-rk3399`

After installing a custom kernel, U-Boot picks up the new kernel and DTB from `/boot` automatically via `extlinux/extlinux.conf`.
