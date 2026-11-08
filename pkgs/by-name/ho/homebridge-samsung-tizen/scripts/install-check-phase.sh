# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
plugin="$out/lib/node_modules/homebridge-samsung-tizen"
@nodejs_24@/bin/node @nodeModulesCheck@ plugin-esm "$plugin/dist/index.js"
runHook postInstallCheck
