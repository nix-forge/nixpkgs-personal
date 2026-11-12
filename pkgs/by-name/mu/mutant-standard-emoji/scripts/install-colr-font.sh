# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm444 build/MutantStandardEmoji.ttf \
  "$out/share/fonts/truetype/MutantStandardEmoji.ttf"
doc="$out/share/doc/mutant-standard-emoji"
mkdir -p "$doc"
cp license.txt credits.txt 'design credits.txt' "$doc/"
cp @readme@ "$doc/README.md"
runHook postInstall
