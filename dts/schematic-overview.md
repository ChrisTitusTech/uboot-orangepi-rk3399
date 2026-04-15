[cite_start]This breakdown provides the technical specifics from the **Orange Pi 800** (v1.8) schematic [cite: 1] required to develop a Linux Device Tree Source (DTS) file. [cite_start]The device is based on the **Rockchip RK3399** SoC[cite: 12128].

### 1. System-on-Chip (SoC) & Memory
* [cite_start]**SoC**: Rockchip RK3399 (Dual-core Cortex-A72 + Quad-core Cortex-A53)[cite: 1, 12128].
* [cite_start]**DRAM**: LPDDR4 interface[cite: 5].
* [cite_start]**Storage (eMMC)**: Connected via 8-bit interface using pins `EMMC_D0` through `EMMC_D7`, `EMMC_CMD`, and `EMMC_CLKO`[cite: 24].
    * [cite_start]**Voltage**: Supports `VCC3V3_S3` and `VCC1V8_S3`[cite: 24].

### 2. Power Management (PMIC & Regulators)
[cite_start]The power architecture centers around the **RK808-D PMIC** (typically located on Page 9)[cite: 15].
* **PMIC Interface**: Connected via **I2C0**.
* **Critical Rails for DTS**:
    * [cite_start]**VDD_LOG**: 0.9V - 1.0V (Logic core supply)[cite: 11981, 12143].
    * [cite_start]**VDD_CPU_L**: Little-core cluster supply[cite: 12207].
    * [cite_start]**VDD_CPU_B**: Big-core cluster supply[cite: 11914, 12244].
    * [cite_start]**VDD_GPU**: GPU power rail[cite: 12040, 12318].
    * [cite_start]**VCC3V3_SYS**: Main 3.3V system rail[cite: 6, 24].
    * [cite_start]**VCC1V8_S3**: 1.8V I/O rail for eMMC and peripherals[cite: 6, 24].
    
    Refinement: While VCC1V8_S3 is used for I/O, the eMMC flash core power is indeed supplied by VCC3V3_S3

### 3. Connectivity (Network & Wireless)
* **Ethernet (RGMII)**: Uses a Motorcomm **YT8531** PHY connected to the RK3399's GMAC.
    * [cite_start]**Interface**: RGMII[cite: 33].
    * **PHY Address**: 1 (Standard for this board design).
* [cite_start]**WiFi/Bluetooth (AP6256)**: Connected via SDIO 0[cite: 4, 16].
    * [cite_start]**WL_REG_ON**: Controlled by `GPIO0_B2`[cite: 4].
    * [cite_start]**WL_HOST_WAKE**: Monitored on `GPIO0_B2`[cite: 16].
    * **BT_REG_ON**: Controlled by `GPIO0_B5` (standard AP6256 implementation).
    * [cite_start]**BT_WAKE**: `BT_WAKE_L` signal[cite: 16].
    * [cite_start]**Interface**: Uses `UART0` for Bluetooth data[cite: 15].

### 4. Peripherals & Audio
* **Keyboard**: Unlike standard SBCs, the Orange Pi 800 has an integrated keyboard.
    * **Connection**: Internal **USB interface**. [cite_start]The schematic shows `USB0-DP` and `USB0-DM` signals routed to the keyboard controller (Page 27)[cite: 34].
    * [cite_start]**Control**: There is a `KEY_CONTROL` signal on `GPIO1_C4`[cite: 15].
* **Audio (ES8316)**: I2S-based codec.
    * **Interface**: `I2S0` or `I2S1` for audio data.
    * [cite_start]**Control**: `I2C1` or `I2C4` (Check I2C bus 1/4)[cite: 15].
* [cite_start]**HDMI**: Standard RK3399 HDMI output using `I2C7` for DDC (Data Display Channel)[cite: 6].

### 5. DTS-Ready Hardware Pin Mapping
| Component | Bus/Pin | DTS Node/Property |
| :--- | :--- | :--- |
| **PMIC** | I2C0 | `rk808@1b` |
| **eMMC** | SDHCI | `sdhci` (8-bit, `bus-width = <8>`) |
| **SD Card** | SDMMC | `sdmmc` (`cap-sd-highspeed`) |
| **Ethernet** | GMAC | `gmac` (`phy-mode = "rgmii"`) |
| **WiFi** | SDIO0 | `sdio0` (`brcm,bcm4329-fmac`) |
| **Bluetooth** | UART0 | `uart0` (`brcm,bcm43438-bt`) |
| **HDMI** | I2C7 | `hdmi` (`pinctrl-0 = <&i2c7_xfer>`) |
| **Audio** | I2C1/4 | `es8316@11` |

### 6. Recommended DTS Structure Example
To assist your build, ensure your DTS file includes these specific nodes for the Orange Pi 800:

```dts
// WiFi Regulator/Enable
vcc_wifi: vcc-wifi-regulator {
    compatible = "regulator-fixed";
    enable-active-high;
    gpio = <&gpio0 RK_PB2 GPIO_ACTIVE_HIGH>; [cite_start]// WL_REG_ON [cite: 4]
    regulator-name = "vcc_wifi";
};

// Ethernet PHY
&gmac {
    phy-supply = <&vcc3v3_s3>;
    phy-mode = "rgmii";
    snps,reset-gpio = <&gpio3 RK_PB7 GPIO_ACTIVE_LOW>;
    status = "okay";
};

// Internal USB Keyboard
&usb_host0_ehci {
    status = "okay"; [cite_start]// Keyboard is often connected here [cite: 34]
};
```