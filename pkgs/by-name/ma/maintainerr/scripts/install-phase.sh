# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

app="$out/libexec/maintainerr"
mkdir -p "$app/apps/server/dist" "$app/apps/server/node_modules" \
  "$app/packages/contracts" "$out/bin" "$out/share/doc/maintainerr"

cp -R node_modules "$app/"
cp -R apps/server/dist/. "$app/apps/server/dist/"
cp apps/server/package.json "$app/apps/server/package.json"
if [ -d apps/server/node_modules ]; then
  cp -R apps/server/node_modules/. "$app/apps/server/node_modules/"
fi
cp -R apps/ui/dist "$app/apps/server/dist/ui"
cp -R apps/server/assets "$app/apps/server/dist/assets"
cp -R packages/contracts/dist "$app/packages/contracts/dist"
cp packages/contracts/package.json "$app/packages/contracts/package.json"
if [ -d packages/contracts/node_modules ]; then
  cp -R packages/contracts/node_modules "$app/packages/contracts/node_modules"
else
  mkdir "$app/packages/contracts/node_modules"
fi

# Retain only runtime artifacts from source-built native addons.
rm -rf \
  "$app/node_modules/better-sqlite3/prebuilds" \
  "$app/node_modules/better-sqlite3/deps" \
  "$app/node_modules/better-sqlite3/src" \
  "$app/node_modules/better-sqlite3/build/Release/obj.target" \
  "$app/node_modules/better-sqlite3/build/Release/.deps" \
  "$app/node_modules/canvas/build/Release/obj.target" \
  "$app/node_modules/canvas/build/Release/.deps" \
  "$app/node_modules/sharp/src/build/Release/obj.target" \
  "$app/node_modules/sharp/src/build/Release/.deps" \
  "$app/node_modules/sharp/src/build/Release/node-addon-api"
rm -f \
  "$app/node_modules/better-sqlite3/build/Release/sqlite3.a" \
  "$app/node_modules/better-sqlite3/build/Release/test_extension.node"
find "$app/node_modules/@img" -mindepth 1 -maxdepth 1 -type d \
  -name 'sharp-*' -exec rm -rf -- {} +

install -Dm755 docker/start.sh "$out/libexec/maintainerr/start.sh"
substituteInPlace "$out/libexec/maintainerr/start.sh" \
  --replace-fail '#!/bin/sh' '#!@stdenv_shell@' \
  --replace-fail '/opt/app/apps/server' "$app/apps/server" \
  --replace-fail 'user the container runs as' 'service user'
makeWrapper "$out/libexec/maintainerr/start.sh" "$out/bin/maintainerr" \
  --prefix PATH : @buildToolsPath@

install -Dm644 LICENSE "$out/share/doc/maintainerr/LICENSE"
runHook postInstall
