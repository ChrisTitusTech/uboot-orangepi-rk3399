# Copilot Instructions — uboot-orangepi-800

## Project Purpose

This is an Arch Linux ARM PKGBUILD that builds and packages U-Boot for the **Orange Pi 800** single-board computer. It produces a pacman package (`uboot-orangepi-800`) which installs U-Boot bootloader images and a boot script onto the target system, and includes a pacman install hook to flash them to an SD card.

---

## Board: Orange Pi 800

| Property | Value |
|---|---|
| SoC | Rockchip RK3399 (dual Cortex-A72 + quad Cortex-A53) |
| Form factor | Keyboard-PC |
| RAM | 4GB LPDDR4 |
| eMMC | 64GB (always present, non-removable) |
| SD card slot | microSD |
| Power | 5V USB-C |
| Serial console | ttyS2 @ 1500000 baud, 8N1 |
| Earlycon | `uart8250,mmio32,0xff1a0000` |
| Ethernet node | `ethernet@fe300000` (GMAC) |
| Ethernet PHY | YT8531C (Motorcomm 1GbE, PHY addr=1) |
| Compatible string | `xunlong,orangepi-800`, `rockchip,rk3399` |

### Storage device numbering

Because the eMMC (`&sdhci`, `non-removable`) is always present and probed first:
- **eMMC** → `/dev/mmcblk0`
- **SD card** → `/dev/mmcblk1`

This is different from boards that have no eMMC (where SD = mmcblk0). The install hook correctly targets `/dev/mmcblk1` for SD card installs.

---

## U-Boot Build

| Property | Value |
|---|---|
| U-Boot version | 2022.04 (pre-built FIT image, sourced from Manjaro ARM 22.07) |
| Architecture | aarch64 (`buildarch=8`) |
| Source | NOT built from source — pre-built `idbloader.img` + `u-boot.itb` committed to repo |

**No OPi 800-specific U-Boot defconfig exists** anywhere. The pre-built binaries from Manjaro ARM 22.07 are used directly; they were compiled with `orangepi-rk3399_defconfig`.

### Bootloader images and flash offsets

| Image | Description | SD card offset (sectors) |
|---|---|---|
| `idbloader.img` | DDR init + miniloader (SPL) | seek=64 |
| `u-boot.itb` | U-Boot FIT image with integrated TF-A/bl31 (replaces old `uboot.img` + `trust.img`) | seek=16384 |

**Note:** The old three-file format (`idbloader.img` + `uboot.img` + `trust.img`) was used with U-Boot 2020.01. U-Boot 2022.04 uses a single `u-boot.itb` FIT image that bundles U-Boot + TF-A. There is no `trust.img` and no seek=24576 write.

---

## Boot Configuration (`extlinux.conf`)

U-Boot 2022.04 uses the `extlinux` distro boot mechanism. No `boot.scr` is needed.

- **Config file**: `/boot/extlinux/extlinux.conf` on the boot partition
- **DTB**: `/dtbs/rockchip/rk3399-orangepi-800.dtb` (paths relative to boot partition root)
- **Boot args**: `console=ttyS2,1500000 root=PARTUUID=<uuid> rw rootwait`
- **Kernel**: `/Image` (AArch64 uncompressed)
- **Initramfs**: `/initramfs-linux.img`

---

## Kernel / DTB Requirement

> **Critical**: `rk3399-orangepi-800.dtb` is **only available in the OrangePi vendor kernel**, NOT in the mainline Linux kernel and NOT in the standard Arch Linux ARM `linux-aarch64` package.

- Vendor kernel repo: [orangepi-xunlong/linux-orangepi](https://github.com/orangepi-xunlong/linux-orangepi)
- Branch: `orange-pi-5.10-rk3399`
- DTS file: `arch/arm64/boot/dts/rockchip/rk3399-orangepi-800.dts`
- **No AUR package exists** for the vendor kernel — users must build it manually from source.

The DTB bundled in this package (sourced from Manjaro ARM 22.07) is sufficient to boot with Ethernet. Full hardware inventory from schematic V1.8 (2022-11-08): PMIC=RK808-D, ETH PHY=YT8531C (Motorcomm), WiFi/BT=AP6256 (BCM43456, brcmfmac), Audio=ES8316, Keyboard MCU=HT68FB571 (USB HID), VGA bridge=CH7517 (eDP→VGA), RTC=BL5372. All OPi 800-specific peripherals require the vendor kernel built from source.

---

## SD Card Partition Layout

| Property | Value |
|---|---|
| Partition table | GPT |
| Partition 1 start | sector 62500 (= ~30 MB from start) |
| Partition 1 size | ~256 MB |
| Partition 1 type | FAT32 (0700) — `/boot` |
| Partition 1 filesystem | vfat |
| Partition 2 start | after partition 1 |
| Partition 2 type | Linux (8300) — `/` |
| Partition 2 filesystem | ext4 |

The ~30 MB gap before the first partition is required because `u-boot.itb` (U-Boot 2022.04 FIT image) is larger than the old `uboot.img` and extends closer to the 16 MB boundary. The 62500-sector start (confirmed from working Manjaro ARM 22.07 image) provides safe clearance.

The boot partition (partition 1) contains: kernel (`Image`), initramfs, `dtbs/` directory, and `extlinux/extlinux.conf`.

---

## File Map

| File | Purpose |
|---|---|
| `PKGBUILD` | Arch Linux package build script (no source build — packages pre-built binaries) |
| `idbloader.img` | Pre-built DDR init + miniloader SPL (from Manjaro ARM 22.07) |
| `u-boot.itb` | Pre-built U-Boot 2022.04 FIT image with TF-A (from Manjaro ARM 22.07) |
| `rk3399-orangepi-800.dtb` | Device tree blob for the OPi 800 (from Manjaro ARM 22.07 vendor kernel) |
| `extlinux.conf` | extlinux boot config template installed to `/boot/extlinux/extlinux.conf` |
| `uboot-orangepi-800.install` | pacman install/upgrade hook — flashes images to `/dev/mmcblk1` |
| `orangepi800/` | Reference docs: OPi 800 schematic + flashing guide PDF |
| `boot.txt` | Legacy U-Boot boot script source (kept for reference, not used) |
| `mkscr` | Legacy helper to compile `boot.txt` → `boot.scr` (not used) |

---

## Known Constraints and Decisions

- **Pre-built binaries**: `idbloader.img`, `u-boot.itb`, and `rk3399-orangepi-800.dtb` are extracted from Manjaro ARM 22.07. They are committed to the repo as source files.
- **DTB bundled**: `rk3399-orangepi-800.dtb` is NOT in the mainline `linux-aarch64` package, so the package ships it to ensure the board boots out of the box. Installed to `/boot/dtbs/rockchip/rk3399-orangepi-800.dtb`. Marked as `backup=` so pacman won't clobber it on upgrade if the user has a newer vendor kernel DTB.
- **extlinux.conf default root**: The shipped `extlinux.conf` uses `root=/dev/mmcblk1p2`. The install README instructs users to replace this with `root=PARTUUID=<uuid>` via `sed` before first boot. Since `extlinux.conf` is in `backup=`, pacman won't overwrite a user-edited version on upgrade.
- **U-Boot version**: 2022.04-3 (as shipped in Manjaro ARM 22.07). Uses FIT image format (`u-boot.itb`), NOT the old split `uboot.img`+`trust.img` format.
- **No trust.img**: U-Boot 2022.04 integrates TF-A into the `u-boot.itb` FIT image. The old `trust.img` at seek=24576 is NOT used.
- **Install target**: `/dev/mmcblk1` (SD card). Do NOT change to mmcblk0 — that is the eMMC.
- **Scope**: SD card boot only. eMMC install is a separate use case.
- **Boot method**: `extlinux.conf` (U-Boot distro boot), NOT `boot.scr`. The `boot.txt`/`mkscr` files are kept for historical reference only.
- **Partition table**: GPT (NOT MBR). First partition starts at sector 62500.
- **SD card setup extraction**: The README uses `bsdtar -xf uboot-orangepi-800-*.pkg.tar.zst -C boot --strip-components=1 boot/` to extract the package's `/boot/` contents directly onto the FAT boot partition before first boot.

---

## Verification Checklist

After any change, verify:
1. `makepkg` completes cleanly (no build step needed — just packages pre-built files).
2. `md5sums` array in PKGBUILD matches actual files — recalculate with `md5sum idbloader.img u-boot.itb extlinux.conf` if any source files change.
3. Flash SD (GPT, partition 1 at sector 62500), insert into OPi 800, power on — U-Boot banner appears on serial (ttyS2 @ 1500000).
4. U-Boot finds `extlinux/extlinux.conf` on the boot partition and loads `/Image`.
5. Kernel boots with `rk3399-orangepi-800.dtb` from the OrangePi vendor kernel.
6. Ethernet (`ethernet@fe300000`) comes up in the booted system.
