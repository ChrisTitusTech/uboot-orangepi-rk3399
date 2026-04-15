Generate locale (uncomment /etc//locale.gen and run `locale-gen`):
```bash
sed -i 's/^#\s*\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
```

Enable NetworkManager to get networking working:
```bash
systemctl enable NetworkManager --now
```

uncommnet %wheel in /etc/sudoers to allow users in the wheel group to use sudo:
```bash
sed -i 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+ALL\)/\1/' /etc/sudoers
```

Set timezone automatically based on geolocation:
```bash
timedatectl set-ntp true
timedatectl set-timezone "$(curl -s --fail https://ipapi.co/timezone)"
```

## Smooth 1080p Video Playback

Hardware video decode on the RK3399 requires the OrangePi vendor kernel. The stock
`linux-aarch64` kernel does **not** include the RK3399 VPU driver.

### Step 1 — Build and install the vendor kernel (mandatory)

On the Orange Pi 800, clone and build:

```bash
git clone --depth=1 -b orange-pi-5.10-rk3399 https://github.com/orangepi-xunlong/linux-orangepi
cd linux-orangepi
make orangepi_defconfig
make -j$(nproc) Image dtbs modules
make modules_install
cp arch/arm64/boot/Image /boot/
cp arch/arm64/boot/dts/rockchip/rk3399-orangepi-800.dtb /boot/dtbs/rockchip/
```

### Step 2 — Reserve contiguous memory for the VPU

Add `cma=256M` to the kernel command line so the VPU has enough DMA-contiguous
memory for 1080p decode buffers:

```bash
sed -i 's/rootwait/rootwait cma=256M/' /boot/extlinux/extlinux.conf
```

### Step 3 — Install Mesa and VA-API

```bash
pacman -S mesa libva-mesa-driver
```

Panfrost (the open-source Mali T860 driver built into Mesa) handles GPU-accelerated
compositing. No proprietary firmware blobs are needed.

### Step 4 — Install MPV and configure hardware decode

```bash
pacman -S mpv
```

Create the MPV config to use V4L2 M2M hardware decode:

```bash
mkdir -p ~/.config/mpv
cat > ~/.config/mpv/mpv.conf << 'EOF'
hwdec=v4l2m2m-copy
vo=gpu
gpu-context=drm
EOF
```

### Step 5 — Set the GPU clock governor to performance

The Mali T860 defaults to a low-power DVFS state which causes frame drops. Create a
udev rule to lock it to the performance governor at boot:

```bash
cat > /etc/udev/rules.d/50-gpu-performance.rules << 'EOF'
SUBSYSTEM=="devfreq", KERNEL=="ff9a0000.gpu", ACTION=="add", ATTR{governor}="performance"
EOF
```

To apply immediately without rebooting:

```bash
echo performance > /sys/class/devfreq/ff9a0000.gpu/governor
```

### Result

With all five steps complete, MPV will offload H.264/H.265/VP8/VP9 decode to the
RK3399 VPU via `v4l2m2m`, keeping CPU usage low and enabling smooth 1080p@60 playback.
