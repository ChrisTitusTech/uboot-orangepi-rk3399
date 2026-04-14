#!/usr/bin/env bash
# copy-to-emmc.sh — Migrate a running SD-card install to the on-board eMMC
# Target board: OrangePi 800 (RK3399)
#   /dev/mmcblk0  =  eMMC  (non-removable, always present)
#   /dev/mmcblk1  =  SD card (current boot device)
#
# Run as root while booted from the SD card.
# The script will partition, format, copy, flash U-Boot, fix extlinux.conf and
# fstab, verify the result, then offer to power off.

set -euo pipefail

# ─── colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()     { echo -e "${RED}[FATAL]${RESET} $*" >&2; exit 1; }
heading() { echo -e "\n${BOLD}${CYAN}==> $*${RESET}"; }

# ─── constants ───────────────────────────────────────────────────────────────
EMMC_DEV="/dev/mmcblk0"
EMMC_BOOT_PART="${EMMC_DEV}p1"
EMMC_ROOT_PART="${EMMC_DEV}p2"
MNT_BASE="/mnt/emmc"
MNT_BOOT="${MNT_BASE}/boot"
MNT_ROOT="${MNT_BASE}/root"
UBOOT_IDB="/boot/idbloader.img"
UBOOT_ITB="/boot/u-boot.itb"
EXTLINUX_DEST="${MNT_BOOT}/extlinux/extlinux.conf"

# ─── cleanup trap ────────────────────────────────────────────────────────────
_cleanup() {
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    warn "Script exited with error (rc=$rc) — attempting cleanup..."
  fi
  # Unmount only if mounted; suppress errors so we always attempt both
  if mountpoint -q "${MNT_BOOT}" 2>/dev/null; then
    umount "${MNT_BOOT}" 2>/dev/null || true
  fi
  if mountpoint -q "${MNT_ROOT}" 2>/dev/null; then
    umount "${MNT_ROOT}" 2>/dev/null || true
  fi
  # Remove mount dirs only if they are empty (don't remove if still occupied)
  rmdir "${MNT_BOOT}" "${MNT_ROOT}" "${MNT_BASE}" 2>/dev/null || true
}
trap _cleanup EXIT

# ─── prerequisite checks ─────────────────────────────────────────────────────
heading "Prerequisite checks"

[[ $EUID -eq 0 ]] || die "Must be run as root."

for cmd in parted mkfs.fat mkfs.ext4 rsync dd blkid mountpoint sync partprobe; do
  command -v "$cmd" &>/dev/null || die "Required tool not found: $cmd  (install with pacman -S dosfstools e2fsprogs rsync parted util-linux)"
done
ok "All required tools present."

# Verify the source device is a real block device
[[ -b "${EMMC_DEV}" ]] || die "${EMMC_DEV} does not exist — is this an OrangePi 800?"

# Confirm the target really is an eMMC (type = "MMC"), not an SD card
EMMC_TYPE=$(cat "/sys/block/mmcblk0/device/type" 2>/dev/null || true)
[[ "${EMMC_TYPE}" == "MMC" ]] || die "${EMMC_DEV} device type is '${EMMC_TYPE}', expected 'MMC'. Refusing to continue."
ok "${EMMC_DEV} is eMMC (type=${EMMC_TYPE})."

# Confirm we are currently booted from the SD card (/dev/mmcblk1)
# Check that root filesystem is on mmcblk1 (not mmcblk0, which would mean
# we're already running from eMMC).
ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
if [[ "${ROOT_DEV}" == /dev/mmcblk0* ]]; then
  die "Root filesystem appears to be on ${EMMC_DEV} — you are already running from eMMC!"
fi
ok "Currently booted from ${ROOT_DEV} (not eMMC)."

# Confirm U-Boot images are present
[[ -f "${UBOOT_IDB}" ]] || die "${UBOOT_IDB} not found — package uboot-orangepi-800 may not be installed."
[[ -f "${UBOOT_ITB}" ]] || die "${UBOOT_ITB} not found — package uboot-orangepi-800 may not be installed."
ok "U-Boot images found: ${UBOOT_IDB}, ${UBOOT_ITB}"

# Confirm extlinux.conf exists on the current boot partition
[[ -f "/boot/extlinux/extlinux.conf" ]] || die "/boot/extlinux/extlinux.conf not found."
ok "extlinux.conf found."

# ─── show disk info & final warning ──────────────────────────────────────────
heading "Disk information"
echo ""
echo "  CURRENT ROOT  : ${ROOT_DEV}"
echo "  TARGET eMMC   : ${EMMC_DEV}  ($(lsblk -dno SIZE "${EMMC_DEV}" 2>/dev/null || echo 'unknown size'))"
echo ""
warn "ALL DATA ON ${EMMC_DEV} WILL BE PERMANENTLY DESTROYED."
warn "This includes any factory Android or OrangePi OS image on the eMMC."
echo ""
read -rp "$(echo -e "${BOLD}Type  YES  to continue:${RESET} ")" CONFIRM
[[ "${CONFIRM}" == "YES" ]] || { info "Aborted by user."; exit 0; }
echo ""

# ─── step 1: partition ───────────────────────────────────────────────────────
heading "Step 1/9 — Partitioning ${EMMC_DEV}"
# Unmount any existing eMMC partitions that may be mounted
for part in "${EMMC_DEV}"p*; do
  [[ -b "$part" ]] || continue
  if mountpoint -q "$part" 2>/dev/null || grep -q "^$part " /proc/mounts 2>/dev/null; then
    info "Unmounting $part first..."
    umount "$part" || die "Could not unmount $part — unmount it manually and retry."
  fi
done

parted -s "${EMMC_DEV}" mklabel gpt
parted -s "${EMMC_DEV}" mkpart boot fat32 62500s 320MiB
parted -s "${EMMC_DEV}" set 1 boot on
parted -s "${EMMC_DEV}" mkpart root ext4 320MiB 100%
partprobe "${EMMC_DEV}" 2>/dev/null || true
# Give the kernel a moment to expose the new partition nodes
for i in 1 2 3 4 5; do
  [[ -b "${EMMC_BOOT_PART}" && -b "${EMMC_ROOT_PART}" ]] && break
  sleep 1
done
[[ -b "${EMMC_BOOT_PART}" ]] || die "Partition ${EMMC_BOOT_PART} not found after partprobe."
[[ -b "${EMMC_ROOT_PART}" ]] || die "Partition ${EMMC_ROOT_PART} not found after partprobe."
ok "Partitioned: ${EMMC_BOOT_PART} (boot, FAT32), ${EMMC_ROOT_PART} (root, ext4)"

# ─── step 2: format ──────────────────────────────────────────────────────────
heading "Step 2/9 — Formatting partitions"
mkfs.fat -F32 -n BOOT "${EMMC_BOOT_PART}"
mkfs.ext4 -L ROOT -F "${EMMC_ROOT_PART}"
ok "Formatted ${EMMC_BOOT_PART} (FAT32, label=BOOT) and ${EMMC_ROOT_PART} (ext4, label=ROOT)"

# ─── step 3: mount ───────────────────────────────────────────────────────────
heading "Step 3/9 — Mounting eMMC partitions"
mkdir -p "${MNT_BOOT}" "${MNT_ROOT}"
mount "${EMMC_BOOT_PART}" "${MNT_BOOT}"
mount "${EMMC_ROOT_PART}" "${MNT_ROOT}"
ok "Mounted at ${MNT_BOOT} and ${MNT_ROOT}"

# ─── step 4: copy boot partition ─────────────────────────────────────────────
heading "Step 4/9 — Copying /boot to eMMC boot partition"
cp -a /boot/. "${MNT_BOOT}/"
ok "Boot partition copied."

# ─── step 5: copy root filesystem ────────────────────────────────────────────
heading "Step 5/9 — Copying root filesystem (this will take several minutes)"
mkdir -p \
  "${MNT_ROOT}/proc" "${MNT_ROOT}/sys" "${MNT_ROOT}/dev" \
  "${MNT_ROOT}/run"  "${MNT_ROOT}/tmp" "${MNT_ROOT}/mnt"

rsync -aAX --one-file-system \
  --exclude=/proc  --exclude=/sys  --exclude=/dev \
  --exclude=/run   --exclude=/tmp  --exclude=/mnt \
  --info=progress2 \
  / "${MNT_ROOT}/"
ok "Root filesystem copied."

# ─── step 6: flash U-Boot to eMMC raw sectors ────────────────────────────────
heading "Step 6/9 — Flashing U-Boot to ${EMMC_DEV} (raw sectors)"
sync
dd if="${UBOOT_IDB}" of="${EMMC_DEV}" seek=64    conv=notrunc,fsync status=progress
dd if="${UBOOT_ITB}"  of="${EMMC_DEV}" seek=16384 conv=notrunc,fsync status=progress
ok "idbloader.img → seek=64, u-boot.itb → seek=16384"

# ─── step 7: update extlinux.conf ────────────────────────────────────────────
heading "Step 7/9 — Updating extlinux.conf with eMMC root PARTUUID"
EMMC_ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${EMMC_ROOT_PART}")
[[ -n "${EMMC_ROOT_PARTUUID}" ]] || die "Could not read PARTUUID from ${EMMC_ROOT_PART}"
info "eMMC root PARTUUID = ${EMMC_ROOT_PARTUUID}"
sed -i "s|root=[^ ]*|root=PARTUUID=${EMMC_ROOT_PARTUUID}|g" "${EXTLINUX_DEST}"
# Verify the substitution landed
grep -q "root=PARTUUID=${EMMC_ROOT_PARTUUID}" "${EXTLINUX_DEST}" \
  || die "PARTUUID substitution in extlinux.conf failed — check manually"
ok "extlinux.conf updated: root=PARTUUID=${EMMC_ROOT_PARTUUID}"

# ─── step 8: update fstab ────────────────────────────────────────────────────
heading "Step 8/9 — Writing /etc/fstab on eMMC root"
EMMC_BOOT_UUID=$(blkid -s UUID -o value "${EMMC_BOOT_PART}")
EMMC_ROOT_UUID=$(blkid -s UUID -o value "${EMMC_ROOT_PART}")
[[ -n "${EMMC_BOOT_UUID}" ]] || die "Could not read UUID from ${EMMC_BOOT_PART}"
[[ -n "${EMMC_ROOT_UUID}" ]] || die "Could not read UUID from ${EMMC_ROOT_PART}"
info "eMMC boot partition UUID = ${EMMC_BOOT_UUID}"
info "eMMC root partition UUID = ${EMMC_ROOT_UUID}"
printf "# Generated by copy-to-emmc.sh\n" > "${MNT_ROOT}/etc/fstab"
printf "UUID=%-40s /boot  vfat  defaults  0 2\n" "${EMMC_BOOT_UUID}" >> "${MNT_ROOT}/etc/fstab"
printf "UUID=%-40s /      ext4  defaults  0 1\n" "${EMMC_ROOT_UUID}" >> "${MNT_ROOT}/etc/fstab"
ok "fstab written."

# ─── step 9: verify ──────────────────────────────────────────────────────────
heading "Step 9/9 — Verification"

# 9a. Check U-Boot IDB magic (0x4e534d52 / "RMSN" at byte 0 of sector 64 = offset 32768)
IDB_MAGIC_ACTUAL=$(dd if="${EMMC_DEV}" bs=512 skip=64 count=1 2>/dev/null | head -c 4 | xxd -p 2>/dev/null || true)
IDB_MAGIC_EXPECTED=$(head -c 4 "${UBOOT_IDB}" | xxd -p 2>/dev/null || true)
if [[ -n "${IDB_MAGIC_ACTUAL}" && "${IDB_MAGIC_ACTUAL}" == "${IDB_MAGIC_EXPECTED}" ]]; then
  ok "U-Boot IDB magic matches at eMMC sector 64 (${IDB_MAGIC_ACTUAL})"
else
  warn "U-Boot IDB magic check inconclusive (actual=${IDB_MAGIC_ACTUAL:-?}, expected=${IDB_MAGIC_EXPECTED:-?}) — dd may have buffered; recommend manual verify after reboot."
fi

# 9b. Check the kernel image exists on the eMMC boot partition
if [[ -f "${MNT_BOOT}/Image" ]]; then
  ok "Kernel image present at ${MNT_BOOT}/Image"
else
  warn "Kernel image not found at ${MNT_BOOT}/Image — check your SD boot partition."
fi

# 9c. Confirm extlinux.conf looks sane
if grep -q "root=PARTUUID=${EMMC_ROOT_PARTUUID}" "${EXTLINUX_DEST}"; then
  ok "extlinux.conf has correct PARTUUID."
else
  warn "extlinux.conf may not have the correct PARTUUID — inspect ${EXTLINUX_DEST} manually."
fi

# 9d. Quickly compare file counts (boot)
SD_BOOT_COUNT=$(find /boot -type f | wc -l)
EMMC_BOOT_COUNT=$(find "${MNT_BOOT}" -type f | wc -l)
if [[ "${SD_BOOT_COUNT}" -eq "${EMMC_BOOT_COUNT}" ]]; then
  ok "Boot partition file count matches (${SD_BOOT_COUNT} files)."
else
  warn "Boot partition file count mismatch: SD=${SD_BOOT_COUNT}, eMMC=${EMMC_BOOT_COUNT} — inspect manually."
fi

# 9e. Print fstab for visual confirmation
echo ""
info "eMMC /etc/fstab:"
cat "${MNT_ROOT}/etc/fstab"

# ─── unmount ─────────────────────────────────────────────────────────────────
heading "Unmounting"
sync
umount "${MNT_BOOT}"
umount "${MNT_ROOT}"
rmdir "${MNT_BOOT}" "${MNT_ROOT}" "${MNT_BASE}" 2>/dev/null || true
# Prevent the trap from trying to unmount again
trap - EXIT
ok "Unmounted cleanly."

# ─── done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗"
echo    "║   eMMC migration complete — all checks passed        ║"
echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
info "Next steps:"
echo "  1. Power off:   poweroff"
echo "  2. Remove the SD card from the slot."
echo "  3. Power on — U-Boot will boot from eMMC (mmcblk0) automatically."
echo "  4. The SD card is now free for other use."
echo ""
read -rp "$(echo -e "${BOLD}Power off now? [y/N]:${RESET} ")" DO_POWEROFF
if [[ "${DO_POWEROFF}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  poweroff
fi
