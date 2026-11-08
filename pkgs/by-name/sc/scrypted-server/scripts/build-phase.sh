# shellcheck shell=bash
runHook preBuild
test -f src/scrypted-main.ts
test ! -e dist/scrypted-main.js
npm run build
npm rebuild @scrypted/node-pty classic-level sharp \
  --build-from-source --offline --ignore-scripts=false
test -n "$(find node_modules/classic-level/build/Release -maxdepth 1 -name '*.node' -print -quit)"
test -n "$(find node_modules/sharp/src/build/Release -maxdepth 1 -name '*.node' -print -quit)"
npm prune --omit=dev --ignore-scripts --offline
runHook postBuild
