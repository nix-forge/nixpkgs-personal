# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Applications/Microsoft Teams.app/Contents/Info.plist"
test -x "$out/Applications/Microsoft Teams.app/Contents/MacOS/MSTeams"
test -x "$out/bin/teams"
runHook postInstallCheck
