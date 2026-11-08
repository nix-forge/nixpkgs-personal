# shellcheck shell=bash
runHook preBuild
pnpm --filter client run build-only
pnpm --filter server run build
runHook postBuild
