# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/LinearMouse.app/Contents/Info.plist"
test -x "$out/Applications/LinearMouse.app/Contents/MacOS/LinearMouse"
runHook postInstallCheck
