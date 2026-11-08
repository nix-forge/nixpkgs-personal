# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
cd "$out/libexec/maintainerr/apps/server" || exit
node @nodeModulesCheck@ require better-sqlite3 canvas sharp
test -f dist/main.js
test -f dist/ui/index.html
test -d dist/assets/fonts
runHook postInstallCheck
