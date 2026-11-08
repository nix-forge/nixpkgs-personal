# shellcheck shell=bash
# Nix supplies builder variables and rendered dependency paths.
# shellcheck disable=SC2154
# This rendered immutable notices dependency is independently ShellChecked.
# shellcheck source=/dev/null
source @gitNotices@
for notice in LICENSE-MIT LICENSE-APACHE NOTICE; do
  install -Dm644 "$notice" "$out/share/doc/@hostName@/$notice"
done
(
  cd @cargoDeps@ || exit
  find -L . -type f \( -iname '*license*' -o -name 'OFL*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'NOTICE*' -o -name 'COPYING*' \) \
    -print0 | while IFS= read -r -d "" notice; do
    install -Dm644 "$notice" "$out/share/doc/@hostName@/dependencies/$notice"
  done
)
install -Dm644 @fonts@/fonts/noto-sans-cjk-sc/OFL.txt "$out/share/doc/@hostName@/noto-sans-cjk-sc/OFL.txt"
install -Dm644 @japaneseFontLicense@ "$out/share/doc/@hostName@/noto-sans-cjk-jp/OFL.txt"
