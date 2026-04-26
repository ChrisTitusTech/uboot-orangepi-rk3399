Use this on the Orange Pi 800 after copying the new DTB.

Copy DTB and reboot:
sudo install -m 0644 /path/to/rk3399-orangepi-800.dtb /boot/dtbs/rockchip/rk3399-orangepi-800.dtb
sync
sudo reboot

After reboot, run these checks in order:

A) DTB and boot path check
uname -a
cat /proc/cmdline
dmesg | grep -Ei "Device Tree|OF:|rk3399-orangepi-800"

B) Storage mapping check (eMMC should be mmcblk0, SD should be mmcblk1)
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
dmesg | grep -Ei "mmcblk0|mmcblk1|dwmmc|sdhci"

C) Ethernet and PHY check
ip link
dmesg | grep -Ei "gmac|stmmac|yt8531|ethernet"

D) WiFi SDIO check
dmesg | grep -Ei "brcmfmac|mmc1|sdio|ap6256"

E) Bluetooth UART check
dmesg | grep -Ei "hci|bluetooth|uart0|ttyS0|brcm"

F) Internal keyboard via USB host check
lsusb
dmesg | grep -Ei "hid|keyboard|usb"

G) Audio codec check
aplay -l
dmesg | grep -Ei "es8316|i2s|sound"

H) PMIC/regulator check
dmesg | grep -Ei "rk808|regulator"

If you want a quick pass/fail log, run:
mkdir -p ~/opi800-validate &&
( uname -a; cat /proc/cmdline; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT; ip link; lsusb; aplay -l; dmesg ) > ~/opi800-validate/validation.log

