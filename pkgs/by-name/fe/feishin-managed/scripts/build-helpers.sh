# shellcheck shell=bash
runHook preBuild
npm exec -- tsc --project tsconfig.json --outDir dist
runHook postBuild
