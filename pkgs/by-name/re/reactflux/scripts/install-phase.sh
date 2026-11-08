# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/share/reactflux"
cp -r build/. "$out/share/reactflux/"
install -Dm444 LICENSE "$out/share/doc/reactflux/LICENSE"
runHook postInstall
