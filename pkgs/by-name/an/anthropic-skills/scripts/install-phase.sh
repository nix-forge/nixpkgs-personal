# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
python3 @catalog_py@ install "$src" --manifest @catalog_json@ \
  --selection @selection@ --output "$out"
install -Dm644 @readme@ "$out/share/doc/@pname@/PACKAGING.md"
runHook postInstall
