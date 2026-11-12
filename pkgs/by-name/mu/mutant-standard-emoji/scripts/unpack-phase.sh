# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preUnpack
python -m zipfile -e "$src" source
cd source || exit
runHook postUnpack
