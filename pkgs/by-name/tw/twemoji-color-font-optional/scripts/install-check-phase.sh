# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
cmp "$src/LICENSE-CC-BY.txt" "$out/share/doc/twemoji-color-font-optional/LICENSE-CC-BY.txt"
cmp "$src/LICENSE-MIT.txt" "$out/share/doc/twemoji-color-font-optional/LICENSE-MIT.txt"
test "$(find "$out/share/fonts" -type f | wc -l)" -gt 0
test ! -e "$out/etc/fonts"
runHook postInstallCheck
