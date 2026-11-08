# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm444 build/metabrainz.js "$out/metabrainz.js"
test -s "$out/metabrainz.js"
runHook postInstall
