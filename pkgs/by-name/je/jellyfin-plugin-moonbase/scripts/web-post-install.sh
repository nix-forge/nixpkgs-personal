# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
# Moonbase serves this dynamically from the plugin configuration.
rm -f "$out/config.json"
