# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
install -Dm644 LICENSE-CC-BY.txt "$out/share/doc/twemoji-color-font-optional/LICENSE-CC-BY.txt"
install -Dm644 LICENSE-MIT.txt "$out/share/doc/twemoji-color-font-optional/LICENSE-MIT.txt"
rm -rf "$out/etc/fonts"
