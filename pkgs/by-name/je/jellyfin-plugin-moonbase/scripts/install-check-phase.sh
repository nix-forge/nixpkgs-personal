# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Moonfin.Server.dll"
test -s "$out/SharpCompress.dll"
test -s "$out/frontend/index.html"
test -s "$out/frontend/assets/NOTICES"
test -s "$out/frontend/theme/index.html"
jq -e --arg version "$version" --arg targetAbi @targetAbi@ \
  '.version == $version and .targetAbi == $targetAbi and .autoUpdate == false' \
  "$out/meta.json" >/dev/null
runHook postInstallCheck
