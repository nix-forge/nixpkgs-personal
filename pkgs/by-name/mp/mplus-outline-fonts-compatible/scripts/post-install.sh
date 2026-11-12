# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
install -Dm644 "$src/OFL.txt" "$out/share/doc/mplus-outline-fonts-compatible/OFL.txt"
rm \
  "$out/share/fonts/truetype/MPLUS1Code[wght].ttf" \
  "$out/share/fonts/truetype/MPLUS1[wght].ttf" \
  "$out/share/fonts/truetype/MPLUS2[wght].ttf" \
  "$out/share/fonts/truetype/MPLUSCodeLatin[wdth,wght].ttf"
