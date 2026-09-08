#!/usr/bin/env bash
set -euo pipefail
base_available=false
changed_files=''
if [[ -n $BASE_SHA && ! $BASE_SHA =~ ^0+$ ]] &&
  git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null &&
  changed_files=$(git diff --name-only "$BASE_SHA" HEAD); then
  base_available=true
else
  echo '::notice::Base history unavailable; rebuilding all current packages.'
fi

all_packages=$(nix eval --json ".#packages.$SYSTEM" --apply builtins.attrNames | jq -r '.[]')
if [[ $base_available == false ]] || grep -qE '^(flake\.nix|flake\.lock|pkgs/default\.nix)$' <<<"$changed_files"; then
  targets="$all_packages"
elif grep -q '^pkgs/by-name/' <<<"$changed_files"; then
  targets=$(sed -nE 's#^pkgs/by-name/[^/]+/([^/]+)/.*#\1#p' <<<"$changed_files" | sort -u)
  targets=$(comm -12 <(sort <<<"$targets") <(sort <<<"$all_packages"))
else
  targets=""
fi

if [[ -z $targets ]]; then
  echo "No packages for $SYSTEM were affected."
  exit 0
fi

# Metadata and documentation can change without changing a build recipe.
# If the base cannot be evaluated, conservatively rebuild every target.
base_derivations='{}'
if [[ $base_available == true ]]; then
  if ! base_derivations=$(nix eval --json \
    "git+file://$PWD?rev=$BASE_SHA#packages.$SYSTEM" \
    --no-write-lock-file --option allow-import-from-derivation false \
    --apply 'builtins.mapAttrs (_: package: package.drvPath)'); then
    echo '::notice::Base derivation comparison unavailable; rebuilding selected packages.'
    base_derivations='{}'
  fi
fi

while IFS= read -r package; do
  [[ -n $package ]] || continue
  echo "::group::Package: $package"
  base_drv=$(jq -r --arg package "$package" '.[$package] // empty' <<<"$base_derivations")
  current_drv=$(nix eval --raw ".#packages.$SYSTEM.$package.drvPath")
  if [[ -n $base_drv && $base_drv == "$current_drv" ]]; then
    echo "$package: unchanged derivation; no rebuild needed."
  else
    bash .github/scripts/build-with-fetch-retry.sh \
      nix build ".#$package" --keep-going --show-trace --print-build-logs
  fi
  # Additional contracts run even when the package output is unchanged.
  if [[ $package == openai-codex-desktop ]]; then
    nix build --no-link --keep-going --show-trace --print-build-logs \
      ".#checks.$SYSTEM.openai-codex-desktop-updater" \
      ".#checks.$SYSTEM.openai-codex-desktop-package-contract"
  fi
  echo "::endgroup::"
done <<<"$targets"
