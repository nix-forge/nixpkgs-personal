# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -d "$out/Applications" "$out/bin"
cp -a Claude.app "$out/Applications/"
ln -s "$out/Applications/Claude.app/Contents/MacOS/Claude" "$out/bin/@pname@"

runHook postInstall
