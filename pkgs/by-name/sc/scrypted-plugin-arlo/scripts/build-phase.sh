# shellcheck shell=bash
runHook preBuild
test -f src/main.py
test ! -e dist/plugin.zip
NODE_ENV=production npm run build
runHook postBuild
