# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

bash ../check-elf.sh "$out/lib/libsteam-cef-scale-override.so"

runHook postInstallCheck
