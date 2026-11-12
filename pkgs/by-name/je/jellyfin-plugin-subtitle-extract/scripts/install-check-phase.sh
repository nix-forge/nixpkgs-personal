# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Jellyfin.Plugin.SubtitleExtract.dll"
jq -e --arg version "$version" --arg targetAbi @targetAbi@ \
  '.version == $version and .targetAbi == $targetAbi and .autoUpdate == false' \
  "$out/meta.json" >/dev/null
runHook postInstallCheck
