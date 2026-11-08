# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/LibreOffice.app/Contents/Info.plist"
test -x "$out/Applications/LibreOffice.app/Contents/MacOS/soffice"
test -x "$out/bin/libreoffice"
runHook postInstallCheck
