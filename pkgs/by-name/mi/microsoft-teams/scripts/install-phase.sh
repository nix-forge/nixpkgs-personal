# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -d "$out/Applications" "$out/bin"
pbzx -n MicrosoftTeams_app.pkg/Payload | cpio -idm -D "$out/Applications"
ln -s "$out/Applications/Microsoft Teams.app/Contents/MacOS/MSTeams" "$out/bin/teams"

runHook postInstall
