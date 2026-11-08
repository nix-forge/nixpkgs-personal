# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/Moonfin.Server.dll"
test -s "$out/SharpCompress.dll"
runHook postInstallCheck
