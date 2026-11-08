# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out"
cp dist/*.cjs dist/*.mjs "$out/"
install -Dm644 @licenseFile@ "$out/share/licenses/homelab-iot-scripts/LICENSE"
runHook postInstall
