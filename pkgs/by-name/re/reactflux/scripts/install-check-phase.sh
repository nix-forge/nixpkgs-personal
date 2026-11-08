# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/share/reactflux/index.html"
test -s "$out/share/reactflux/manifest.webmanifest"
test -s "$out/share/reactflux/sw.js"
runHook postInstallCheck
