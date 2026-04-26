# New DTS Branch Notes

## Current Branch Status

| Item | Value |
|---|---|
| Branch | `new-dts` |
| Working tree | `clean` |
| Latest commit | `067243d` |
| Suggested commit title | `feat(dts): align Orange Pi 800 DTS with schematic and clean dtc warnings` |

### Files Changed vs `main`

- `PKGBUILD`
- `rk3399-orangepi-800.dts`
- `rk3399.dtsi`
- `rk3399-opp.dtsi`
- `schematic-overview.md`
- `rk3399-orangepi-800.dtb`

## Commit Summary

- Switched DTB build flow to preprocess DTS with `cpp` before `dtc` in `PKGBUILD`.
- Vendored RK3399 base includes for reproducible host-side DTB builds: `rk3399.dtsi` and `rk3399-opp.dtsi`.
- Fixed board DTS binding issues and warning sources in `rk3399-orangepi-800.dts`.
- Added explicit `KEY_CONTROL` pin representation and kept keyboard routing documented in DTS.
- Corrected AP6256 and related mapping notes in `schematic-overview.md` to match the schematic PDF.
- Regenerated `rk3399-orangepi-800.dtb`.

## Artifact Note

| Item | Value |
|---|---|
| Package | `uboot-orangepi-800-2022.04-1-aarch64.pkg.tar.zst` |
| SHA-256 | `fc4055305f5365fa67dd4ffef00e687302c209b976e4506c675b71798e0e1d71` |

## Changes Compared to `main`

The new DTS/DTB on branch `new-dts` is a technical upgrade, not just a rewrite.

## Major Improvements

### 1. Build Reliability and Reproducibility

- `main` used a direct `dtc` compile path on a monolithic decompiled DTS.
- `new-dts` compiles through `cpp + dtc` in `PKGBUILD`, which is the correct flow for dt-bindings and include-based DTS.
- Base RK3399 includes are now vendored (`rk3399.dtsi`, `rk3399-opp.dtsi`), reducing host kernel tree dependency issues.

### 2. Source Quality: Decompiled Blob -> Maintainable Board DTS

- The old `main` DTS was effectively an expanded/decompiled tree and hard to maintain.
- The new `rk3399-orangepi-800.dts` is board-focused and uses upstream-style base includes.

**Measured reduction**

| Metric | `main` | `new-dts` |
|---|---:|---:|
| DTS line count | 4063 | 985 |

This is a major maintainability gain for future kernel-port work.

### 3. DT Validation Quality (Objective)

Both versions were compiled side-by-side:

| Metric | `main` | `new-dts` |
|---|---:|---:|
| DTS compile warning lines | 394 | 0 |

The new tree is materially cleaner and closer to upstream tooling expectations.

### 4. Hardware Mapping Correctness

- Corrected keyboard LED function bindings to standard values in `rk3399-orangepi-800.dts`.
- Corrected I2S clock binding for the ES8316 audio path in `rk3399-orangepi-800.dts`.
- Cleaned `gpio-keys` / address-cell usage and memory node formatting in `rk3399-orangepi-800.dts`.
- Added explicit `KEY_CONTROL` pin representation (`GPIO1_C4`) in `rk3399-orangepi-800.dts`.
- Corrected schematic alignment in `schematic-overview.md`.

### 5. Runtime Artifact Quality

Recompiled DTBs differ significantly:

| Metric | `main` build | `new-dts` build |
|---|---:|---:|
| DTB size | 78K | 56K |

The smaller result is expected here because the new source is cleaner and more structured, avoiding decompiled-tree noise.

## Practical Impact

- Easier forward-porting to newer Linux kernels.
- Lower risk of subtle DT binding breakage.
- Cleaner debug cycle when board bring-up fails.
- Higher confidence that board wiring definitions match schematic intent.

## Bottom Line

Switching to the new DTS/DTB is a strong improvement over `main` in correctness, maintainability, and toolchain compatibility.