# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/Wootility.app/Contents/Info.plist"
test -x "$out/Applications/Wootility.app/Contents/MacOS/Wootility"
test -x "$out/bin/wootility"
runHook postInstallCheck
