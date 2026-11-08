# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/index.html"
test -s "$out/flutter_bootstrap.js"
test -s "$out/main.dart.js"
test -s "$out/main.dart.mjs"
test -s "$out/main.dart.wasm"
test -s "$out/assets/NOTICES"
test -s "$out/sqlite3.wasm"
runHook postInstallCheck
