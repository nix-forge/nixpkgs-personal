# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -Dm755 "$(swiftpmBinPath)/finder-favorites" \
  "$out/bin/finder-favorites"
install -Dm644 README.md "$out/share/doc/finder-favorites/README.md"
install -Dm644 LICENSE "$out/share/doc/finder-favorites/LICENSE"

runHook postInstall
