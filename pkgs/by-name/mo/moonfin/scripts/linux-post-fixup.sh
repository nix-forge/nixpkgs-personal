# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
patchelf "$out/app/moonfin/moonfin" \
  --add-needed libmpv.so --add-needed libsqlite3.so \
  --add-rpath @mediaLibraryPath@
