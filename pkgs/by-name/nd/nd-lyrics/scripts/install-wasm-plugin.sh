# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm444 target/wasm32-wasip1/release/navidrome_lyrics_plugin.wasm \
  "$out/plugin.wasm"
runHook postInstall
