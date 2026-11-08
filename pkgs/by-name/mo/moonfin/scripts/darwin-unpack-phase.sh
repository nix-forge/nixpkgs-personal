# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preUnpack
7zz x -y -sns- "$src" >/dev/null
runHook postUnpack
