# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
install -d "$iconRoot/@theme@"
cp -R --no-preserve=mode,ownership "build/@theme@/@theme@/." "$iconRoot/@theme@/"
