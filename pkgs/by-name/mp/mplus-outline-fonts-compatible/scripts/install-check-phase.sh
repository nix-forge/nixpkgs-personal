# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
cmp "$src/OFL.txt" "$out/share/doc/mplus-outline-fonts-compatible/OFL.txt"
test "$(find "$out/share/fonts" -type f | wc -l)" -gt 0
test ! -e "$out/share/fonts/truetype/MPLUS1[wght].ttf"
runHook postInstallCheck
