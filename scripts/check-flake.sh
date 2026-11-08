#!/usr/bin/env bash
set -euo pipefail

# Keep development-partition files available before evaluating check derivations.
nix store add-path flake/dev
# All per-system outputs share the flake's supportedSystems list. Release each
# evaluator before the next system so package sets do not accumulate in memory.
systems=$(nix eval --json .#checks --apply builtins.attrNames | jq -er '.[]')
while IFS= read -r system; do
  nix eval --option allow-import-from-derivation false --json ".#checks.$system" \
    --apply 'builtins.mapAttrs (_: check: check.drvPath)' >/dev/null
  nix flake check --system "$system" --no-build --option allow-import-from-derivation false
done <<<"$systems"
