# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preUnpack

7zz x -sns- "$src"

runHook postUnpack
