# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
destination="$out/share/scrypted/plugins/@scrypted/homekit"
mkdir -p "$destination"
tar -xzf "$src" --strip-components=1 -C "$destination" \
  package/package.json package/dist/plugin.zip package/README.md package/LICENSE
runHook postInstall
