# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/Moonfin.app/Contents/Info.plist"
test -x "$out/Applications/Moonfin.app/Contents/MacOS/Moonfin"
test -x "$out/bin/moonfin"
runHook postInstallCheck
