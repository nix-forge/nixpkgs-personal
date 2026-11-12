# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/share/doc/craft-fonts"
# Keep each font with its license, and retain the upstream manifest/attribution.
cp -r fonts "$out/fonts"
cp ATTRIBUTION.md LICENSE-MIT LICENSE-APACHE "$out/share/doc/craft-fonts/"
runHook postInstall
