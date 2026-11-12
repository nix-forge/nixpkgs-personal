# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
destination="$out/share/scrypted/plugins/@scrypted/arlo"
mkdir -p "$destination"
install -Dm644 package.json "$destination/package.json"
install -Dm644 dist/plugin.zip "$destination/dist/plugin.zip"
install -Dm644 README.md "$destination/README.md"
runHook postInstall
