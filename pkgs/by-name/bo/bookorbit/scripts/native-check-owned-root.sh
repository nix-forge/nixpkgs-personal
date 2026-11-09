# shellcheck shell=bash
# PRoot supplies an owned filesystem view inside the existing Nix sandbox.
# Preserve the real invoking identity; do not use its root/identity emulation.
swc_test_root=$(@coreutils@/bin/mktemp -d "$NIX_BUILD_TOP/swc-test-root.XXXXXXXXXX")
@coreutils@/bin/mkdir -p "$swc_test_root/nix/store" "$swc_test_root/proc" \
  "$swc_test_root/dev" "$swc_test_root/tmp" "$swc_test_root$NIX_BUILD_TOP"
@proot@/bin/proot \
  --rootfs="$swc_test_root" \
  --bind=/nix/store --bind="$NIX_BUILD_TOP" --bind=/proc --bind=/dev \
  --cwd="$PWD" \
  @nativeCheckCommand@ || return $?
unset swc_test_root
