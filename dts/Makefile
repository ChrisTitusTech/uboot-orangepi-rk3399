DTC      ?= dtc
DTC_FLAGS = -I dts -O dtb -W no-unit_address_vs_reg

DTB = rk3399-orangepi-800.dtb

all: $(DTB)

%.dtb: %.dts
	$(DTC) $(DTC_FLAGS) -o $@ $<

clean:
	rm -f $(DTB)

.PHONY: all clean
