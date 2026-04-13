# uboot-orangepi-800

U-Boot 2022.04 bootloader package for the **Orange Pi 800** (Rockchip RK3399). Pre-built binaries sourced from Manjaro ARM 22.07.

This package provides everything needed to boot: the bootloader images, a baseline `extlinux.conf`, and the `rk3399-orangepi-800.dtb` device tree (not included in the stock `linux-aarch64` package).

---

## Requirements

- An SD card (8GB or larger recommended)
- A host machine running Linux
- `gdisk`, `mkfs.fat`, `mkfs.ext4`, `bsdtar` (`libarchive`), `dd`, `blkid`
- The `uboot-orangepi-800` package, built locally (see [Building](#building))

---

## Building the package

Build on any machine (no cross-compiler needed — ships pre-built binaries):

```bash
git clone https://github.com/jakogut/uboot-orangepi-rk3399
cd uboot-orangepi-rk3399
makepkg -s
```

This produces `uboot-orangepi-800-2022.04-1-aarch64.pkg.tar.zst` (or similar). Keep it in the current directory for the steps below.

---

## Install Arch Linux ARM on an SD Card

Replace **`sdX`** with the device name for your SD card (e.g. `sdb`). Run all commands as **root**.

### Step 1 — Wipe the beginning of the SD card

```bash
dd if=/dev/zero of=/dev/sdX bs=1M count=64
```

### Step 2 — Create a GPT partition table

```bash
gdisk /dev/sdX
```

At the `gdisk` prompt:

1. Press **`o`** → **`y`** — create a new empty GPT partition table
2. Press **`n`** → **`1`** → enter `62500` as the first sector → `+256M` as the last sector → **`0700`** as the type (FAT32 boot partition)
3. Press **`n`** → **`2`** → press **Enter** for the default first sector → **Enter** for the default last sector → **`8300`** as the type (Linux root partition)
4. Press **`w`** → **`y`** — write and exit

> The first partition must start at sector **62500** (~30 MB from the start) to leave room for the U-Boot images.

### Step 3 — Format the partitions

```bash
mkfs.fat -F32 /dev/sdX1
mkfs.ext4 /dev/sdX2
```

### Step 4 — Mount the partitions

```bash
mkdir -p boot root
mount /dev/sdX1 boot
mount /dev/sdX2 root
```

### Step 5 — Download and extract the Arch Linux ARM root filesystem

```bash
wget https://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C root
sync
```

### Step 6 — Move /boot to the boot partition

```bash
mv root/boot/* boot/
```

### Step 7 — Extract the U-Boot package files onto the boot partition

This installs the bootloader images, the DTB, and the extlinux config directly onto the FAT boot partition:

```bash
bsdtar -xf uboot-orangepi-800-*.pkg.tar.zst -C boot --strip-components=1 boot/
```

### Step 8 — Set the root partition PARTUUID in extlinux.conf

```bash
ROOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/sdX2)
sed -i "s|root=/dev/mmcblk1p2|root=PARTUUID=${ROOT_PARTUUID}|" boot/extlinux/extlinux.conf
```

### Step 9 — Set up fstab

```bash
BOOT_UUID=$(blkid -s UUID -o value /dev/sdX1)
ROOT_UUID=$(blkid -s UUID -o value /dev/sdX2)
cat >> root/etc/fstab << EOF
UUID=${BOOT_UUID}  /boot  vfat  defaults  0  2
UUID=${ROOT_UUID}  /      ext4  defaults  0  1
EOF
```

### Step 10 — Copy the U-Boot package for post-boot installation

```bash
cp uboot-orangepi-800-*.pkg.tar.zst root/home/alarm/
```

### Step 11 — Flash U-Boot to the SD card

```bash
dd if=boot/idbloader.img of=/dev/sdX seek=64    conv=notrunc,fsync
dd if=boot/u-boot.itb    of=/dev/sdX seek=16384 conv=notrunc,fsync
```

### Step 12 — Unmount

```bash
umount boot root
sync
```

### Step 13 — Boot the Orange Pi 800

1. Insert the SD card into the Orange Pi 800.
2. Connect an Ethernet cable.
3. Apply 5V USB-C power.

U-Boot scans the boot partition for `extlinux/extlinux.conf` and loads the kernel automatically.

### Step 14 — Log in

Connect via serial console (**ttyS2, 1500000 baud, 8N1**) or SSH to the IP address assigned by your router.

| Account | Username | Password |
|---|---|---|
| User | `alarm` | `alarm` |
| Root | `root` | `root` |

### Step 15 — Initialize pacman and install the package

```bash
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu
pacman -U /home/alarm/uboot-orangepi-800-*.pkg.tar.zst
```

The `.install` hook will offer to reflash U-Boot to the SD card (now from inside the running system).

### Step 16 — Install the vendor kernel (optional but recommended)

The bundled `rk3399-orangepi-800.dtb` is from Manjaro ARM 22.07. For the latest device support (keyboard, WiFi/BT, etc.), install the OrangePi vendor kernel which ships a newer DTB:

```bash
# Example using an AUR helper — adjust for your preferred method
yay -S linux-aarch64-orangepi
```

After installing, reboot. U-Boot will pick up the new kernel and DTB from `/boot` automatically.
