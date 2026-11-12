# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out"/bin "$out"/lib/actual/packages/{api,cli}
cp -r packages/api/{dist,package.json} "$out"/lib/actual/packages/api/
cp -r packages/cli/{dist,package.json} "$out"/lib/actual/packages/cli/
cp -r packages/{loot-core,crdt} "$out"/lib/actual/packages/
yarn workspaces focus @actual-app/cli --production
cp -r node_modules "$out"/lib/actual/
makeBinaryWrapper @node@ "$out"/bin/actual-cli \
  --add-flags "$out"/lib/actual/packages/cli/dist/cli.js
runHook postInstall
