# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/lib"
pnpm --filter server --config.inject-workspace-packages=true --prod deploy "$out/lib"
cp -r client/dist "$out/lib/public"
cp -r server/src/db/migrations "$out/lib/migrations"
cp -r koreader-plugin "$out/lib/koreader-plugin"
makeWrapper @nodejs@/bin/node "$out/bin/bookorbit" \
  --run "cd $out/lib" \
  --set NODE_ENV production \
  --set APP_VERSION @version@ \
  --add-flags "$out/lib/dist/main.js"
makeWrapper @nodejs@/bin/node "$out/bin/bookorbit-migrate" \
  --set NODE_ENV production \
  --add-flags "$out/lib/dist/scripts/migrate.js"
runHook postInstall
