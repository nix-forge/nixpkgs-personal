# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
install -Dm644 "$src/LICENSE" "$out/share/doc/noctalia-personal/LICENSE"
# These libraries are compiled into the executable, so retain their notices
# even when they do not survive as separate runtime store references.
for notice in \
  fzy/LICENSE luau/LICENSE.txt luau/lua_LICENSE.txt \
  material_color_utilities/LICENSE wuffs/LICENSE-MIT wuffs/LICENSE-APACHE; do
  install -Dm644 "$src/third_party/$notice" \
    "$out/share/doc/noctalia-personal/third-party/$notice"
done
install -Dm644 @readme@ "$out/share/doc/noctalia-personal/README.md"
