# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
python3 @catalog_py@ verify "$src" --manifest @catalog_json@ \
  --selection @selection@ --output "$out"
runHook postInstallCheck
