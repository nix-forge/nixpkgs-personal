# shellcheck shell=bash
runHook preBuild
pnpm run build
runHook postBuild
