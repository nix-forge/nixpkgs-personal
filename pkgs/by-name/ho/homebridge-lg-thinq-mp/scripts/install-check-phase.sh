# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
plugin="$out/lib/node_modules/@mp-consulting/homebridge-lg-thinq"
test -f "$plugin/config.schema.json"
test -s "$plugin/homebridge-ui/server.js"
test -s "$plugin/homebridge-ui/public/lib/kit.js"
test -s "$plugin/homebridge-ui/public/lib/bootstrap.bundle.min.js"
@nodejs_24@/bin/node @nodeModulesCheck@ plugin-esm "$out/lib/node_modules/@mp-consulting/homebridge-lg-thinq/dist/index.js"
runHook postInstallCheck
