# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
productionBuildDir="$PWD"

# Exercise Meson's sanitizer configuration separately so the installed
# release target retains undefined-symbol rejection and release settings.
meson setup "$NIX_BUILD_TOP/sanitized-build" "$NIX_BUILD_TOP/$sourceRoot" \
  --buildtype=custom \
  -Dauto_features=enabled \
  -Db_asneeded=false \
  -Ddebug=true \
  -Db_lundef=false \
  -Db_ndebug=false \
  -Db_sanitize=address,undefined \
  -Doptimization=1 \
  -Dtests=true \
  -Dwrap_mode=nodownload
meson compile -C "$NIX_BUILD_TOP/sanitized-build" -j "$NIX_BUILD_CORES"
meson test -C "$NIX_BUILD_TOP/sanitized-build" \
  -j "$NIX_BUILD_CORES" --no-rebuild --print-errorlogs

cd "$productionBuildDir" || exit
