# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
# Preserve notices for embedded fonts/icons, dictionaries and vendored libraries.
mkdir -p "$out/share/doc/@pname@/licenses"
find -L . -type f \( -iname '*license*' -o -iname 'OFL*' -o -iname '*attribution*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'COPYING*' -o -name 'NOTICE*' \) \
  -not -path './target/*' -not -path './docs/brand/*' \
  -print0 | while IFS= read -r -d "" notice; do
  install -Dm644 "$notice" "$out/share/doc/@pname@/licenses/$notice"
done
(
  cd @fonts@ || exit
  find fonts -type f -not -iname '*.ttf' -not -iname '*.otf' -print0 |
    while IFS= read -r -d "" notice; do
      install -Dm644 "$notice" "$out/share/doc/@pname@/licenses/craft-fonts/$notice"
    done
)
cp @fonts@/ATTRIBUTION.md "$out/share/doc/@pname@/licenses/craft-fonts/ATTRIBUTION.md"
(
  cd @cargoDeps@ || exit
  mkdir -p "$out/share/doc/@pname@/licenses/dependencies"
  find -L . -type f \( -iname '*license*' -o -name 'OFL*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'COPYING*' -o -name 'NOTICE*' \) \
    -print0 | while IFS= read -r -d "" notice; do
    install -Dm644 "$notice" "$out/share/doc/@pname@/licenses/dependencies/$notice"
  done
)
# This distribution changes packaging and, where needed, removes restricted logos.
printf '%s\n' 'Packaged from source with Nix; see the package recipe for changes.' \
  >"$out/share/doc/@pname@/PACKAGING-NOTICE"
