#
# Local test build only.
#
# For mainline kernel, copy rk3399-orangepi-800.dts to:
#   arch/arm64/boot/dts/rockchip/
# Then add to that directory's Makefile:
#   dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3399-orangepi-800.dtb
# Build with: make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs
#
# The DTS uses #include and dt-bindings headers (cpp required).
# Supply kernel include path with -I.
#
CPP      ?= cpp
DTC      ?= dtc
LINUX_INC ?= /usr/src/linux/include

DTB = rk3399-orangepi-800.dtb

all: $(DTB)

%.dtb: %.dts
	$(CPP) -E -x assembler-with-cpp -I$(LINUX_INC) $< | \
	$(DTC) -I dts -O dtb -W no-unit_address_vs_reg -o $@

clean:
	rm -f $(DTB)

.PHONY: all clean
