# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
@fontPython@/bin/python @finish_py@ "$out" .
