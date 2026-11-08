# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
(
  cd "$cargoDepsCopy" || exit
  patch -p1 <@candle_metal_device_bounds_patch@
  python3 @tests_update_vendor_checksum_py@ candle-core-0.9.2 src/metal_backend/mod.rs
)
