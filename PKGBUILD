# U-Boot: Orange Pi 800
# Pre-built binaries sourced from Manjaro ARM 22.07 (U-Boot 2022.04)
#
# Maintainer: Joseph Kogut <joseph.kogut@gmail.com>

buildarch=8

pkgname=uboot-orangepi-800
pkgver=2022.04
pkgrel=1
pkgdesc="U-Boot for Orange Pi 800"
arch=('aarch64')
url='https://u-boot.readthedocs.io/'
license=('GPL')
makedepends=('dtc')
backup=('boot/extlinux/extlinux.conf'
        'boot/dtbs/rockchip/rk3399-orangepi-800.dtb')
install=${pkgname}.install
source=('idbloader.img'
        'u-boot.itb'
        'extlinux.conf')
md5sums=('d0034efbfeb465732444094b59cabdea'
         'd5ed2a9edda0dbb197a0d38ea987085d'
         'aca02c2c1d70720d5abba09b865ccd10')

build() {
  dtc -I dts -O dtb -W no-unit_address_vs_reg \
      -o rk3399-orangepi-800.dtb \
      "$startdir/dts/rk3399-orangepi-800.dts"
}

package() {
  install -Dm644 idbloader.img          "${pkgdir}/boot/idbloader.img"
  install -Dm644 u-boot.itb             "${pkgdir}/boot/u-boot.itb"
  install -Dm644 extlinux.conf          "${pkgdir}/boot/extlinux/extlinux.conf"
  install -Dm644 rk3399-orangepi-800.dtb "${pkgdir}/boot/dtbs/rockchip/rk3399-orangepi-800.dtb"
}
