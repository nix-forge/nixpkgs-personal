# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/Bitwarden.app/Contents/Info.plist"
test -x "$out/Applications/Bitwarden.app/Contents/MacOS/Bitwarden"
test -x "$out/bin/bitwarden"
runHook postInstallCheck
