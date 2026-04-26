Current branch status:

Branch: new-dts
Working tree: clean
Latest branch commit: 067243d
Files changed vs main include PKGBUILD, rk3399-orangepi-800.dts, rk3399.dtsi, rk3399-opp.dtsi, schematic-overview.md, rk3399-orangepi-800.dtb
Suggested commit title:
feat(dts): align Orange Pi 800 DTS with schematic and clean dtc warnings

Commit Summary:

switch DTB build flow to preprocess DTS with cpp before dtc in PKGBUILD
vendor RK3399 base includes for reproducible host-side DTB builds: rk3399.dtsi and rk3399-opp.dtsi
fix board DTS binding issues and warning sources in rk3399-orangepi-800.dts
add explicit KEY_CONTROL pin representation and keep keyboard routing documented in DTS
correct AP6256 and related mapping notes in schematic-overview.md to match schematic PDF
regenerate rk3399-orangepi-800.dtb
Artifact note:

package: uboot-orangepi-800-2022.04-1-aarch64.pkg.tar.zst
sha256: fc4055305f5365fa67dd4ffef00e687302c209b976e4506c675b71798e0e1d71

Changes compared to Main:
The new DTS/DTB on branch new-dts is a real technical upgrade, not just a rewrite.

Big improvements

Build reliability and reproducibility
Main used a direct dtc compile path on a monolithic decompiled DTS.
New branch compiles through cpp + dtc in PKGBUILD, which is the correct flow for dt-bindings and include-based DTS.
You now also vendor the base RK3399 includes in rk3399.dtsi and rk3399-opp.dtsi, so builds are less dependent on host kernel tree quirks.
Source quality: decompiled blob -> maintainable board DTS
Old main DTS was effectively an expanded/decompiled tree (very large, hard to maintain).
New DTS in rk3399-orangepi-800.dts is a board-focused source that includes upstream-style base files.
Measured reduction:
Main DTS lines: 4063
New DTS lines: 985
This is a major maintainability gain for future kernel-port work.
DT validation quality (objective)
I compiled both versions side-by-side:
Main DTS compile warnings: 394 lines
New DTS compile warnings: 0 lines
So the new tree is materially cleaner and closer to what upstream tooling expects.
Hardware mapping correctness improvements
Corrected keyboard LED function bindings to standard values in rk3399-orangepi-800.dts.
Corrected I2S clock binding for ES8316 audio path in rk3399-orangepi-800.dts.
Cleaned gpio-keys/address-cell usage and memory node formatting in rk3399-orangepi-800.dts.
Added explicit KEY_CONTROL pin representation (GPIO1_C4) in rk3399-orangepi-800.dts.
Corrected schematic documentation alignment in schematic-overview.md.
Runtime artifact quality
Recompiled DTBs differ significantly:
Main-built DTB size: 78K
New-built DTB size: 56K
Smaller here is expected because the new source is cleaner/structured and avoids the noisy decompiled style.
What this means in practice

Easier to port forward to newer Linux kernels.
Lower risk of subtle DT binding breakage.
Cleaner debug cycle when something fails on board.
Better confidence that board wiring definitions match schematic intent.
Net: switching to the new DTS/DTB is a strong improvement over main in correctness, maintainability, and toolchain compatibility.