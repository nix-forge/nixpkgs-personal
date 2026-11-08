# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/Claude.app/Contents/Info.plist"
test -x "$out/Applications/Claude.app/Contents/MacOS/Claude"
test -x "$out/bin/claude-desktop"
runHook postInstallCheck
