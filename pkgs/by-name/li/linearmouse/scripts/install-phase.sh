# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -d "$out/Applications"
cp -a LinearMouse.app "$out/Applications/"

runHook postInstall
