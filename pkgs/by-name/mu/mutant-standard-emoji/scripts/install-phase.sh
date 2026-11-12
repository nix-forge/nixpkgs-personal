# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
cp -R @compiledFont@ "$out"
chmod -R u+w "$out"
install -m444 font.ttf "$out/share/fonts/truetype/MutantStandardEmoji.ttf"
install -m444 @encoding_md@ "$out/share/doc/mutant-standard-emoji/encoding.md"
runHook postInstall
