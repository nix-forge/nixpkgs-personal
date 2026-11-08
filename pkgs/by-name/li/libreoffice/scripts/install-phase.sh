# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -d "$out/Applications/@appName@" "$out/bin"
cp -R . "$out/Applications/@appName@"
ln -s "$out/Applications/@appName@/Contents/MacOS/soffice" "$out/bin/soffice"
ln -s "$out/bin/soffice" "$out/bin/libreoffice"

runHook postInstall
