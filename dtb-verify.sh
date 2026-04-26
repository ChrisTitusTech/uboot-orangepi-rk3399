#!/usr/bin/env bash
set -euo pipefail

# Orange Pi 800 DTB hardware verification helper
# Runs post-boot checks and prints a concise PASS/FAIL report.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

pass_count=0
fail_count=0

section() {
  echo
  echo -e "${BOLD}${BLUE}==> $*${RESET}"
}

status_line() {
  local name="$1"
  local ok="$2"
  local detail="$3"
  if [[ "$ok" == "1" ]]; then
    echo -e "${GREEN}PASS${RESET} | ${name} | ${detail}"
    pass_count=$((pass_count + 1))
  else
    echo -e "${RED}FAIL${RESET} | ${name} | ${detail}"
    fail_count=$((fail_count + 1))
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

cmd_pkg_hint() {
  case "$1" in
    nmtui|nmcli) echo "networkmanager" ;;
    iw) echo "iw" ;;
    rfkill) echo "util-linux" ;;
    *) echo "unknown" ;;
  esac
}

read_dmesg() {
  if dmesg >/dev/null 2>&1; then
    dmesg
    return
  fi

  if have_cmd sudo && sudo -n dmesg >/dev/null 2>&1; then
    sudo -n dmesg
    return
  fi

  return 1
}

contains_any() {
  local haystack="$1"
  shift

  local needle
  for needle in "$@"; do
    if echo "$haystack" | grep -Eiq "$needle"; then
      return 0
    fi
  done
  return 1
}

safe_cmd_output() {
  local cmd="$1"
  if eval "$cmd" >/dev/null 2>&1; then
    eval "$cmd"
  else
    echo ""
  fi
}

section "Collecting System Context"
uname_out=$(uname -a 2>/dev/null || true)
cmdline_out=$(cat /proc/cmdline 2>/dev/null || true)
lsblk_out=$(safe_cmd_output "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT")
ip_link_out=$(safe_cmd_output "ip link")
lsusb_out=$(safe_cmd_output "lsusb")
aplay_out=$(safe_cmd_output "aplay -l")

if dmesg_all=$(read_dmesg); then
  dmesg_ok=1
  echo -e "${GREEN}INFO${RESET} dmesg readable"
else
  dmesg_ok=0
  dmesg_all=""
  echo -e "${YELLOW}WARN${RESET} dmesg not readable (run with root or grant dmesg access)"
fi

section "A) DTB And Boot Path"
if contains_any "$cmdline_out" "rk3399-orangepi-800\.dtb|rockchip/rk3399-orangepi-800\.dtb"; then
  dtb_cmdline=1
else
  dtb_cmdline=0
fi

if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "Device Tree|OF:|rk3399-orangepi-800"; then
  dtb_dmesg=1
else
  dtb_dmesg=0
fi

if [[ "$dtb_cmdline" -eq 1 || "$dtb_dmesg" -eq 1 ]]; then
  status_line "DTB Loaded" 1 "rk3399-orangepi-800 detected in cmdline/dmesg"
else
  status_line "DTB Loaded" 0 "rk3399-orangepi-800 not found in cmdline or dmesg"
fi

section "B) Storage Mapping"
has_mmc0=0
has_mmc1=0
if contains_any "$lsblk_out" "mmcblk0"; then
  has_mmc0=1
fi
if contains_any "$lsblk_out" "mmcblk1"; then
  has_mmc1=1
fi

if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "mmcblk0|mmcblk1|dwmmc|sdhci"; then
  mmc_dmesg=1
else
  mmc_dmesg=0
fi

if [[ "$has_mmc0" -eq 1 && "$has_mmc1" -eq 1 && "$mmc_dmesg" -eq 1 ]]; then
  status_line "Storage eMMC+SD" 1 "mmcblk0 and mmcblk1 visible; mmc driver logs present"
else
  status_line "Storage eMMC+SD" 0 "expected mmcblk0/mmcblk1 and mmc logs not fully present"
fi

section "C) Ethernet And PHY"
if contains_any "$ip_link_out" "eth0|enp"; then
  eth_link=1
else
  eth_link=0
fi

if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "gmac|stmmac|yt8531|ethernet"; then
  eth_dmesg=1
else
  eth_dmesg=0
fi

if [[ "$eth_link" -eq 1 && "$eth_dmesg" -eq 1 ]]; then
  status_line "Ethernet PHY" 1 "interface and driver/PHY logs detected"
else
  status_line "Ethernet PHY" 0 "missing interface or gmac/stmmac/yt8531 logs"
fi

section "D) WiFi SDIO"
if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "brcmfmac|mmc1|sdio|ap6256"; then
  wifi_probe_ok=1
  status_line "WiFi AP6256" 1 "brcmfmac/sdio probe logs detected"
else
  wifi_probe_ok=0
  status_line "WiFi AP6256" 0 "no brcmfmac/sdio/ap6256 evidence in dmesg"
fi

# nmtui readiness means the full userspace stack is present and NM can manage WiFi.
wifi_deps_ok=1
wifi_dep_missing=()
wifi_dep_hints=()
for cmd in nmtui nmcli iw; do
  if ! have_cmd "$cmd"; then
    wifi_deps_ok=0
    wifi_dep_missing+=("$cmd")
    wifi_dep_hints+=("$cmd=$(cmd_pkg_hint "$cmd")")
  fi
done

if [[ "$wifi_deps_ok" -eq 1 ]]; then
  status_line "WiFi Dependencies" 1 "nmtui/nmcli/iw installed"
else
  status_line "WiFi Dependencies" 0 "missing: ${wifi_dep_missing[*]} (install pkgs: ${wifi_dep_hints[*]})"
fi

wifi_fw_ok=0
if ls /usr/lib/firmware/brcm/brcmfmac4345*.bin >/dev/null 2>&1; then
  wifi_fw_ok=1
fi

if [[ "$wifi_fw_ok" -eq 1 ]]; then
  status_line "WiFi Firmware" 1 "Broadcom firmware present under /usr/lib/firmware/brcm"
else
  status_line "WiFi Firmware" 0 "missing brcmfmac firmware (install linux-firmware)"
fi

wifi_iface_ok=0
if contains_any "$ip_link_out" "wlan0|wlp"; then
  wifi_iface_ok=1
fi

nm_service_ok=0
nm_state="unknown"
if have_cmd systemctl; then
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    nm_service_ok=1
    nm_state="active"
  else
    nm_state="inactive"
  fi
fi

rfkill_ok=1
rfkill_note="rfkill not checked"
if have_cmd rfkill; then
  rfkill_out=$(rfkill list 2>/dev/null || true)
  if echo "$rfkill_out" | grep -Eiq "Wireless|wlan|bluetooth"; then
    if echo "$rfkill_out" | grep -Eiq "Soft blocked: yes|Hard blocked: yes"; then
      rfkill_ok=0
      rfkill_note="wireless appears blocked"
    else
      rfkill_note="wireless unblocked"
    fi
  else
    rfkill_note="no wireless rfkill entry"
  fi
fi

if [[ "$wifi_probe_ok" -eq 1 && "$wifi_deps_ok" -eq 1 && "$wifi_iface_ok" -eq 1 && "$nm_service_ok" -eq 1 && "$rfkill_ok" -eq 1 ]]; then
  status_line "WiFi nmtui Ready" 1 "driver+iface+deps+NetworkManager active (${rfkill_note})"
else
  status_line "WiFi nmtui Ready" 0 "requires probe,deps,wifi iface,NM active,unblocked rfkill (nm=${nm_state}; ${rfkill_note})"
  echo -e "${YELLOW}HINT${RESET} Install deps: pacman -S networkmanager iw linux-firmware"
  echo -e "${YELLOW}HINT${RESET} Enable NM: systemctl enable --now NetworkManager"
  echo -e "${YELLOW}HINT${RESET} Unblock radio if needed: rfkill unblock wifi"
fi

section "E) Bluetooth UART"
if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "hci|bluetooth|uart0|ttyS0|brcm"; then
  status_line "Bluetooth" 1 "bluetooth/uart logs detected"
else
  status_line "Bluetooth" 0 "no bluetooth/uart evidence in dmesg"
fi

section "F) Internal Keyboard Via USB"
if contains_any "$lsusb_out" "Linux Foundation|Keyboard|HID|1d6b"; then
  usb_list_ok=1
else
  usb_list_ok=0
fi

if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "hid|keyboard|usb"; then
  usb_dmesg_ok=1
else
  usb_dmesg_ok=0
fi

if [[ "$usb_list_ok" -eq 1 && "$usb_dmesg_ok" -eq 1 ]]; then
  status_line "USB Keyboard/HID" 1 "USB devices listed and HID logs present"
else
  status_line "USB Keyboard/HID" 0 "USB/HID evidence incomplete"
fi

section "G) Audio Codec"
if contains_any "$aplay_out" "card|es8316|rockchip"; then
  audio_list_ok=1
else
  audio_list_ok=0
fi

if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "es8316|i2s|sound"; then
  audio_dmesg_ok=1
else
  audio_dmesg_ok=0
fi

if [[ "$audio_list_ok" -eq 1 && "$audio_dmesg_ok" -eq 1 ]]; then
  status_line "Audio ES8316" 1 "audio card and codec/i2s logs detected"
else
  status_line "Audio ES8316" 0 "missing aplay card output or codec/i2s logs"
fi

section "H) PMIC / Regulators"
if [[ "$dmesg_ok" -eq 1 ]] && contains_any "$dmesg_all" "rk808|regulator"; then
  status_line "PMIC RK808" 1 "rk808/regulator logs detected"
else
  status_line "PMIC RK808" 0 "no rk808/regulator evidence in dmesg"
fi

section "Summary"
echo -e "${GREEN}PASS:${RESET} ${pass_count}"
echo -e "${RED}FAIL:${RESET} ${fail_count}"

if [[ "$fail_count" -eq 0 ]]; then
  echo -e "${BOLD}${GREEN}Overall: PASS${RESET}"
  exit 0
fi

echo -e "${BOLD}${RED}Overall: FAIL${RESET}"
exit 1
