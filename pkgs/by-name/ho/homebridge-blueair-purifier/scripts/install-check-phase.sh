# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
plugin="$out/lib/node_modules/homebridge-blueair-purifier"
test -f "$plugin/config.schema.json"
test -f "$plugin/homebridge-ui/server.js"
@nodejs_24@/bin/node @nodeModulesCheck@ plugin-cjs "$plugin"
runHook postInstallCheck
