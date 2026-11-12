# shellcheck shell=bash
runHook preBuild
@yarn@ turbo build
YARN_ENABLE_SCRIPTS=false @yarn@ workspaces focus --all --production
runHook postBuild
