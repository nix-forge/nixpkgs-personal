# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -f "$out/lib/node_modules/@scrypted/server/dist/scrypted-main.js"
test -f "$out/lib/node_modules/@scrypted/server/python/plugin_remote.py"
@nodejs_24@/bin/node @nodeModulesCheck@ require "$out/lib/node_modules/@scrypted/server/dist/scrypted-main-exports.js"
@nodejs_24@/bin/node @nodeModulesCheck@ require "$out/lib/node_modules/@scrypted/server/node_modules/@scrypted/node-pty"
@nodejs_24@/bin/node @nodeModulesCheck@ require "$out/lib/node_modules/@scrypted/server/node_modules/sharp"
@nodejs_24@/bin/node @nodeModulesCheck@ require "$out/lib/node_modules/@scrypted/server/node_modules/classic-level"
runHook postInstallCheck
