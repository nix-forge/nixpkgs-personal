# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out"
cp -R @wasm@/share "$out/share"
runHook postInstall
