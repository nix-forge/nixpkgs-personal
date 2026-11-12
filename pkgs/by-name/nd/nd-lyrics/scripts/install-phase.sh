# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -d "$out/share"
install -Dm444 @wasm@/plugin.wasm plugin.wasm
zip -q "$out/share/nd-lyrics.ndp" plugin.wasm manifest.json
install -Dm444 LICENSE "$out/share/doc/nd-lyrics/LICENSE"
runHook postInstall
