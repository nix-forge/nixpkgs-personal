# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preUnpack

xar -xf "$src"

runHook postUnpack
