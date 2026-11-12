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
app="$out/lib/node_modules/@scrypted/server"
@nodejs_24@/bin/node @tarCheck@ "$app/node_modules/tar" "$app"
test -f "$app/node_modules/tar/LICENSE.md"
@nodejs_24@/bin/node @proxyAddrCheck@ "$app/node_modules/proxy-addr" "$app"
timeout --kill-after=5s 90s @nodejs_24@/bin/node @cacheCheck@ "$app"
timeout --kill-after=5s 90s @nodejs_24@/bin/node @runtimeCheck@ "$app" @nativeSvgLibrary@
timeout --kill-after=5s 90s @nodejs_24@/bin/node @transportCheck@ "$app"
timeout --kill-after=5s 30s @nodejs_24@/bin/node @forgeCheck@ "$app/node_modules/node-forge"
runHook postInstallCheck
