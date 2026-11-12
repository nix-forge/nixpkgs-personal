# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -d "$out/Applications" "$out/bin"
cp -a Bitwarden.app "$out/Applications/"
ln -s "$out/Applications/Bitwarden.app/Contents/MacOS/Bitwarden" "$out/bin/bitwarden"

runHook postInstall
