# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
runHook preSignSpotifyBundle

app="$out/Applications/Spotify.app"
@rcodesign@ sign \
  --code-signature-flags runtime \
  --entitlements-xml-file @entitlements@ \
  "$app"
test -s "$app/Contents/_CodeSignature/CodeResources"

runHook postSignSpotifyBundle
