# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/Steam.app/Contents/Info.plist"
test -x "$out/Applications/Steam.app/Contents/MacOS/steam_osx"
test -x "$out/bin/steam"
runHook postInstallCheck
