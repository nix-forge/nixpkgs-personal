# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
node --check "$out/lib/dist/main.js"
node --check "$out/lib/dist/scripts/migrate.js"
test -n "$(find "$out/lib/migrations" -type f -print -quit)"
runHook postInstallCheck
