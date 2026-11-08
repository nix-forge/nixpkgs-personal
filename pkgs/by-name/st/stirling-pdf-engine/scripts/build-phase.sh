# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preBuild
python -m compileall -q -s "$PWD" -p "$out/share/stirling-pdf-engine" "$PWD/src"
runHook postBuild
