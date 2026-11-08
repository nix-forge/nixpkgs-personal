# shellcheck shell=bash
patchShebangs node_modules backend/node_modules frontend/node_modules
# Sharp's upstream builder invokes node-gyp; retain the host compiler budget.
export npm_package_config_node_gyp_jobs="$NIX_BUILD_CORES"
: "${npm_config_nodedir:?Node headers must be supplied by the Nix build}"
# Rebuild the declared native addons with Nix headers/toolchains and no downloads.
for module in better-sqlite3 bcrypt sharp; do
  # Sharp 0.35 does not export package.json; use the actual workspace link.
  module_directory=$(realpath "backend/node_modules/$module")
  test -f "$module_directory/package.json"
  (
    cd "$module_directory" || exit
    if [[ $module == sharp ]]; then
      SHARP_FORCE_GLOBAL_LIBVIPS=1 node install/build.js
    else
      # better-sqlite3 13 has no install script and defaults to its prebuild.
      # Force its documented source target; bcrypt uses the same gyp entrypoint.
      # better-sqlite3 prioritizes its prebuild over build/Release at runtime.
      # Remove the vendored addons so both packages use our source-built output.
      rm -rf prebuilds
      node-gyp rebuild --release --force_build=1 \
        --nodedir="$npm_config_nodedir" --jobs="$NIX_BUILD_CORES"
    fi
  )
done

# Upstream checks import Honker before the normal install-time fixup phase.
# Patch only the selected GNU runtime libraries, not other optional platforms.
architecture=$(node -p process.arch)
shopt -s nullglob
honker_native_packages=(node_modules/.pnpm/@russellthehippo+honker-*-linux-"$architecture"-gnu@*/node_modules/@russellthehippo/honker-*-linux-"$architecture"-gnu)
shopt -u nullglob
test "${#honker_native_packages[@]}" -eq 2
autoPatchelf "${honker_native_packages[@]}"
