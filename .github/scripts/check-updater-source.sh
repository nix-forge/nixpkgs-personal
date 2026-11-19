#!/usr/bin/env bash
set -euo pipefail

bash scripts/sync-updater-mirrors.sh

# Revision-dependent tooling uses revCount. A shallow source can list updaters but fails
# when their pinned Nixpkgs is imported, after costly shell realization.
if [[ $(git rev-parse --is-shallow-repository) != false ]]; then
  echo '::error::Package updates require a full-history Git checkout.' >&2
  exit 1
fi
metadata=$(nix flake metadata --json --no-write-lock-file .)
jq -e '.revCount | type == "number" and . > 0' <<<"$metadata" >/dev/null
# Import the same locked package scope used by the native updater dispatcher.
nix eval --impure --no-update-lock-file --option allow-import-from-derivation false \
  --raw --expr 'let source = (builtins.getFlake ("git+file://" + builtins.getEnv "PWD")).inputs.nixpkgs; in (import source {}).lib.version' >/dev/null
