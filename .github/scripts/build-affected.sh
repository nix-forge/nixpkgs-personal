#!/usr/bin/env bash
set -euo pipefail

selected=$(jq -ce '
  select(type == "array" and length > 0 and length == (unique | length)
    and all(.[]; type == "string" and test("^[a-z0-9][a-z0-9+._-]*$")))
' <<<"$PACKAGES")
targets=$(jq -r '.[]' <<<"$selected")

# Bound each evaluator to 32 selected outputs, sharing one map per batch rather
# than starting one evaluator per package/check. Missing base outputs stay absent.
derivation_map() {
  local reference=$1 names=$2 offset batch result='{}' values
  for ((offset = 0; offset < $(jq length <<<"$names"); offset += 32)); do
    batch=$(jq -c --argjson offset "$offset" '.[$offset:$offset+32] | tojson' <<<"$names")
    batch=${batch//\$\{/\\\$\{}
    values=$(nix eval --json "$reference" --no-write-lock-file \
      --option allow-import-from-derivation false \
      --apply "outputs: builtins.mapAttrs (_: value: value.drvPath) (builtins.intersectAttrs (builtins.listToAttrs (map (name: { inherit name; value = null; }) (builtins.fromJSON $batch))) outputs)") || return 1
    jq -e 'type == "object" and all(.[]; type == "string" and test("^/nix/store/[a-z0-9]{32}-.+\\.drv$"))' <<<"$values" >/dev/null || return 1
    result=$(jq -cn --argjson before "$result" --argjson values "$values" '$before + $values')
  done
  printf '%s\n' "$result"
}

current_derivations=$(derivation_map ".#packages.$SYSTEM" "$selected")
jq -e --argjson selected "$selected" 'keys == ($selected | sort)' <<<"$current_derivations" >/dev/null
base_derivations='{}'
if [[ -n $BASE_SHA ]]; then
  if ! base_derivations=$(derivation_map "git+file://$PWD?rev=$BASE_SHA#packages.$SYSTEM" "$selected"); then
    echo '::notice::Base derivation comparison unavailable; rebuilding selected packages.'
    base_derivations='{}'
  fi
fi

while IFS= read -r package; do
  [[ -n $package ]] || continue
  echo "::group::Package: $package"
  base_drv=$(jq -r --arg package "$package" '.[$package] // empty' <<<"$base_derivations")
  current_drv=$(jq -er --arg package "$package" '.[$package]' <<<"$current_derivations")
  if [[ -n $base_drv && $base_drv == "$current_drv" ]]; then
    echo "$package: unchanged derivation; no rebuild needed."
  else
    bash .github/scripts/build-with-fetch-retry.sh \
      nix build ".#$package" --keep-going --show-trace --print-build-logs
  fi
  echo "::endgroup::"
done <<<"$targets"
