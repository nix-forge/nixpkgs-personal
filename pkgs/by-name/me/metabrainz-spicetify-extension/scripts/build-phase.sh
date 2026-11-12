# shellcheck shell=bash
runHook preBuild
tsc --project tsconfig.json --outDir build
runHook postBuild
