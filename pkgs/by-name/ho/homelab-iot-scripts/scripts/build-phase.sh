# shellcheck shell=bash
runHook preBuild
npm run build
runHook postBuild
