# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -d "$out/Applications" "$out/bin"
cp -a Moonfin/Moonfin.app "$out/Applications/"
ln -s "$out/Applications/Moonfin.app/Contents/MacOS/Moonfin" "$out/bin/moonfin"
runHook postInstall
