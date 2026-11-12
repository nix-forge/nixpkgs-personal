# shellcheck shell=bash
runHook preBuild
yarn workspace @actual-app/api exec vite build
yarn workspace @actual-app/cli build
runHook postBuild
