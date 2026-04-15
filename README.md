# uboot-orangepi-800

U-Boot 2022.04 bootloader package for the **Orange Pi 800** (Rockchip RK3399). Pre-built binaries sourced from Manjaro ARM 22.07. These were rebuilt based on this source, with a new dts and dtb as of 26.04.13 for use with arch linux arm. 

This package provides everything needed to boot: the bootloader images, a baseline `extlinux.conf`, and the `rk3399-orangepi-800.dtb` device tree (not included in the stock `linux-aarch64` package).

---

## Requirements

- An SD card (8GB or larger recommended)
- A host machine running Linux
- `parted`, `mkfs.fat`, `mkfs.ext4`, `bsdtar` (`libarchive`), `dd`, `blkid`
- The `uboot-orangepi-800` package built locally (see below)

---

## Build the package

No cross-compiler needed — ships pre-built binaries. The package targets `aarch64` but contains no compiled code, so build it on any Linux host with `--ignorearch`:

```bash
git clone https://github.com/ChrisTitusTech/uboot-orangepi-rk3399
cd uboot-orangepi-rk3399
CARCH=aarch64 makepkg --ignorearch
```

This produces `uboot-orangepi-800-2022.04-1-aarch64.pkg.tar.zst` in the current directory. The `CARCH=aarch64` prefix ensures the package is tagged for the correct architecture regardless of the build host. Keep it there for the steps below.

> **Note**: `makepkg` is an Arch Linux tool. On non-Arch hosts, install it via your distro or use an Arch Linux container. Alternatively, on the OPi 800 itself after first boot you can run `makepkg` natively without `--ignorearch`.

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
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C root --exclude='./boot/dtbs'
mv root/boot/* boot/
```

> The `--exclude='./boot/dtbs'` flag skips the thousands of upstream DTB files for other ARM boards, which would otherwise fill the 256 MB FAT partition. The OPi 800 DTB is installed in Step 4 from the package.

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
mkdir -p root/home/alarm
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
pacman -Sy archlinux-keyring
pacman -U /home/alarm/uboot-orangepi-800-*.pkg.tar.zst
```

The `.install` hook will offer to reflash U-Boot to `/dev/mmcblk1` on install and upgrade.

---

## Optional: Copy Installation to eMMC

Once the system is running from the SD card, you can migrate it to the on-board 64 GB eMMC (`/dev/mmcblk0`) and expand the root partition to fill it. Run all commands as **root** while booted from the SD card.

> **Note**: This will erase everything currently on the eMMC (including any factory Android/OrangePi OS image).

### Step 1 — Install rsync

```bash
pacman -S rsync
```

### Step 2 — Partition the eMMC

```bash
parted -s /dev/mmcblk0 mklabel gpt
parted -s /dev/mmcblk0 mkpart boot fat32 62500s 320MiB
parted -s /dev/mmcblk0 set 1 boot on
parted -s /dev/mmcblk0 mkpart root ext4 320MiB 100%
```

### Step 3 — Format

```bash
mkfs.fat -F32 -n BOOT /dev/mmcblk0p1
mkfs.ext4 -L ROOT /dev/mmcblk0p2
```

### Step 4 — Mount eMMC partitions

```bash
mkdir -p /mnt/emmc/{boot,root}
mount /dev/mmcblk0p1 /mnt/emmc/boot
mount /dev/mmcblk0p2 /mnt/emmc/root
```

### Step 5 — Copy boot partition

```bash
cp -a /boot/. /mnt/emmc/boot/
```

### Step 6 — Copy root filesystem

The `--one-file-system` flag keeps rsync from crossing into `/boot` (FAT) or any other mounted filesystems:

```bash
rsync -aAX --one-file-system \
  --exclude=/proc --exclude=/sys --exclude=/dev \
  --exclude=/run  --exclude=/tmp --exclude=/mnt \
  / /mnt/emmc/root/
```

### Step 7 — Flash U-Boot to eMMC

```bash
dd if=/boot/idbloader.img of=/dev/mmcblk0 seek=64    conv=notrunc,fsync
dd if=/boot/u-boot.itb    of=/dev/mmcblk0 seek=16384 conv=notrunc,fsync
```

### Step 8 — Update extlinux.conf to point at the eMMC root

```bash
EMMC_ROOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p2)
sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=${EMMC_ROOT_PARTUUID}|" \
  /mnt/emmc/boot/extlinux/extlinux.conf
```

### Step 9 — Update /etc/fstab on the eMMC root

```bash
EMMC_BOOT_UUID=$(blkid -s UUID -o value /dev/mmcblk0p1)
EMMC_ROOT_UUID=$(blkid -s UUID -o value /dev/mmcblk0p2)
printf "UUID=%s\t/boot\tvfat\tdefaults\t0 2\nUUID=%s\t/\text4\tdefaults\t0 1\n" \
  "$EMMC_BOOT_UUID" "$EMMC_ROOT_UUID" > /mnt/emmc/root/etc/fstab
```

### Step 10 — Unmount and reboot

```bash
sync
umount /mnt/emmc/boot /mnt/emmc/root
reboot
```

After reboot, U-Boot will find the eMMC bootloader first (eMMC is `mmcblk0`, the primary boot device) and load the kernel from the eMMC boot partition. The SD card can be removed once the eMMC boot is confirmed working.

---

## Notes on Hardware Support

The bundled `rk3399-orangepi-800.dtb` is sourced from Manjaro ARM 22.07. Hardware support status based on the OPi 800 schematic (V1.8, 2022-11-08):

| Hardware | Chip | Works with bundled DTB |
|---|---|---|
| PMIC | RK808-D | ✅ Yes (required for boot) |
| RAM (4GB LPDDR4) | 4× LPDDR4 BGA200 | ✅ Yes |
| eMMC (64GB) | eMMC 5.0 BGA169 | ✅ Yes |
| SD card | TF-CKT01-009D | ✅ Yes |
| Ethernet | YT8531C (Motorcomm 1GbE) | ✅ Yes |
| HDMI output | RK3399 internal | ⚠️ Partial |
| USB 2.0 / USB 3.0 | RK3399 TypeC PHY | ⚠️ Partial |
| WiFi / Bluetooth | AP6256 (BCM43456 via SDIO+UART) | ❌ No — needs vendor kernel + firmware |
| Audio | ES8316 codec (I2C1 + I2S0) | ❌ No — needs vendor kernel |
| Speaker amp | XPT8871 (GPIO-controlled) | ❌ No — needs vendor kernel |
| Keyboard MCU | HT68FB571 (USB HID via USB0) | ❌ No — needs vendor kernel |
| VGA output | CH7517 eDP-to-VGA bridge | ❌ No — no mainline driver |
| RTC | BL5372 (I2C) | ❌ No — needs DTS node |
| 26-pin GPIO header | I2C / SPI / UART / PWM / GPIO | ⚠️ Partial |

For WiFi, the AP6256 uses the standard `brcmfmac` driver but requires firmware from the `linux-firmware` package and proper DTS SDIO/GPIO nodes.

For full hardware support, you must build the OrangePi vendor kernel from source — no AUR package exists:

- Repository: [orangepi-xunlong/linux-orangepi](https://github.com/orangepi-xunlong/linux-orangepi)
- Branch: `orange-pi-5.10-rk3399`

After installing a custom kernel, U-Boot picks up the new kernel and DTB from `/boot` automatically via `extlinux/extlinux.conf`.

---

## Troubleshooting

### No Ethernet

The board boots and HDMI/keyboard work, but Ethernet has no link.

**1. Check if the interface appears (note: it may be named `end0`, not `eth0`):**
```bash
ip link
```

**2. Check kernel messages for GMAC/PHY errors:**
```bash
dmesg | grep -iE 'eth|gmac|phy|motorcomm|yt8|stmmac|dwmac'
```

**Known failure: `stmmac_hw_setup: DMA engine initialization failed`**

This is caused by a PHY driver chain failure:

1. The YT8531C PHY attaches as **`[unbound]` → Generic PHY** because the `motorcomm` kernel module is not loaded.
2. The Generic PHY does not handle the YT8531C's reset GPIO, so the PHY never provides the required 125 MHz RGMII clock to the GMAC.
3. Without that clock, the GMAC DMA reset times out → `Failed to reset the dma` → `DMA engine initialization failed` → `Hw setup failed`.

**Root cause:** The `motorcomm` module must be loaded *before* the `dwmac-rk` GMAC driver probes the PHY bus at boot. If Generic PHY claims the YT8531C first, loading `motorcomm` later won't rebind it — and `ip link set end0 up` will return `RTNETLINK answers: connection timed out` because the GMAC DMA is still waiting for the RGMII clock that Generic PHY never provides.

**Step 1 — make motorcomm load at boot (before GMAC probes):**
```bash
echo "motorcomm" | sudo tee /etc/modules-load.d/motorcomm.conf
reboot
```

**Step 2 — after reboot, confirm motorcomm bound the PHY (not Generic PHY):**
```bash
dmesg | grep -iE 'motorcomm|Generic PHY|stmmac_hw_setup|Failed to reset'
```
You should see `motorcomm` in the PHY driver line and no `DMA engine initialization failed`.

**Step 3 — the interface is named `end0`, not `eth0`**

The kernel renames `eth0` to `end0` via systemd predictable network naming. This is normal, but ALARM's per-interface `dhcpcd@eth0.service` won't apply to `end0`, so the interface stays down even after motorcomm fixes the PHY.

Enable dhcpcd globally so it handles whatever name the interface gets:
```bash
systemctl enable --now dhcpcd.service
```

Or bring it up manually for immediate access:
```bash
ip link set end0 up
dhcpcd end0
```

**Immediate fix without reboot — manually rebind the PHY (if you cannot reboot):**
```bash
echo "stmmac-0:00" > /sys/bus/mdio_bus/drivers/"Generic PHY"/unbind
echo "stmmac-0:00" > /sys/bus/mdio_bus/drivers/motorcomm/bind
ip link set end0 up
dhcpcd end0
```

**Check if the Motorcomm PHY driver is available:**
```bash
modinfo motorcomm 2>/dev/null || echo "module not found"
```

If `modinfo motorcomm` returns "Module not found", the mainline `linux-aarch64` kernel was built without it and the vendor kernel is required (see Hardware Support table above).

**Summary of causes:**

| Cause | Symptom | Fix |
|---|---|---|
| `motorcomm` not loaded at boot | `PHY driver [Generic PHY]`, `Failed to reset the dma`, `connection timed out` | `echo motorcomm > /etc/modules-load.d/motorcomm.conf` + reboot |
| `dhcpcd@eth0.service` active but interface is `end0` | motorcomm loads fine, DMA OK, but no IP address | `systemctl enable --now dhcpcd.service` |
| PHY driver missing from kernel | `modinfo motorcomm` → "Module not found" | Needs vendor kernel |
| DTB/mainline GMAC clock mismatch | `dwmac-rk` probe fails entirely in `dmesg` | Needs vendor kernel |
