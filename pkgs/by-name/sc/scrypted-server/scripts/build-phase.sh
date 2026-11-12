# shellcheck shell=bash
runHook preBuild
# Apply the metadata guard before building the server or running node-gyp.
patch --batch --fuzz=0 --no-backup-if-mismatch -p1 -d node_modules/tar <@tarPatch@
# Rebuild both public entrypoints with upstream's bundle flags.
# Discard only the stale maps for the two modified input modules.
rm node_modules/tar/dist/commonjs/read-entry.js.map node_modules/tar/dist/esm/read-entry.js.map
(
  cd node_modules/tar || exit 1
  esbuild --minify --platform=node --sourcemap --bundle dist/commonjs/index.js \
    --outfile=dist/commonjs/index.min.js --format=cjs
  esbuild --minify --platform=node --sourcemap --bundle dist/esm/index.js \
    --outfile=dist/esm/index.min.js --format=esm
)
test -f src/scrypted-main.ts
test ! -e dist/scrypted-main.js
npm run build
npm rebuild @scrypted/node-pty classic-level \
  --build-from-source --offline --ignore-scripts=false
# Sharp 0.35 builds its native addon through an explicit script.
npm explore sharp -- npm run build
test -n "$(find node_modules/classic-level/build/Release -maxdepth 1 -name '*.node' -print -quit)"
test -n "$(find node_modules/sharp/src/build/Release -maxdepth 1 -name '*.node' -print -quit)"
timeout --kill-after=5s 90s @nodejs_24@/bin/node @cacheCheck@ "$PWD" "$PWD"
npm prune --omit=dev --ignore-scripts --offline
runHook postBuild
