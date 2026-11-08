# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
install -Dm444 assets/icons/moonfin.png \
  "$out/share/icons/hicolor/512x512/apps/org.moonfin.linux.png"
