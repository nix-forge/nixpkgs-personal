# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
(
  cd "$cargoDepsCopy" || exit
  patch -p1 <@rten_vnni_intrinsic_patch@
  python3 @tests_update_vendor_checksum_py@ rten-gemm-0.26.0 src/i8dot.rs
)
