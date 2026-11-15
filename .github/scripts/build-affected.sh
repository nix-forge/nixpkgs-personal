#!/usr/bin/env bash
set -euo pipefail

partition_count=${PARTITION_COUNT:-1}
partition_index=${PARTITION_INDEX:-0}
if [[ ! $partition_count =~ ^[1-9][0-9]*$ || ! $partition_index =~ ^(0|[1-9][0-9]*)$ ]] ||
  ((partition_index >= partition_count)); then
  echo '::error::Invalid package partition count or index.'
  exit 1
fi

# Check every exclusion against the complete package tree, including packages
# unavailable on this runner. A typo must not silently enable a hosted build.
policy=.github/ci-policy.json
if ! jq -e '
  type == "object" and all(to_entries[];
    (.key | test("^[a-z0-9][a-z0-9+._-]*$")) and
    (.value | type == "string" and test("\\S")))
' "$policy" >/dev/null; then
  echo '::error::Invalid hosted-build policy; expected package names and nonblank reasons.'
  exit 1
fi
while IFS= read -r package; do
  if [[ ! -f "pkgs/by-name/${package:0:2}/$package/package.nix" ]]; then
    echo "::error::Hosted-build policy names an unknown package: $package"
    exit 1
  fi
done < <(jq -r 'keys[]' "$policy")

base_available=false
changed_files=''
if [[ -n $BASE_SHA && ! $BASE_SHA =~ ^0+$ ]] &&
  git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null &&
  changed_files=$(git diff --name-only "$BASE_SHA" HEAD); then
  base_available=true
else
  echo '::notice::Base history unavailable; rebuilding all current packages.'
fi

# Discover names without forcing derivations outside this partition/policy.
all_packages=$(nix eval --option allow-import-from-derivation false --json ".#packages.$SYSTEM" \
  --apply builtins.attrNames | jq -r '.[]')
if [[ $base_available == false ]] || grep -qE '^((flake\.nix|flake\.lock|pkgs/default\.nix|\.github/ci-policy\.json)$|flake/|tests/|\.github/(scripts|tests|workflows)/)' <<<"$changed_files"; then
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

targets=$(printf '%s\n' "$targets" | python3 .github/scripts/partition_packages.py \
  --count "$partition_count" --index "$partition_index" \
  --weights .github/ci-package-weights.json)
if [[ -z $targets ]]; then
  echo "No packages for $SYSTEM were assigned to partition $partition_index."
  exit 0
fi

# Exclusions apply before any derivation is forced.
targets=$(while IFS= read -r package; do
  if ! jq -e --arg package "$package" 'has($package)' "$policy" >/dev/null; then
    printf '%s\n' "$package"
  else
    echo "$package: $(jq -r --arg package "$package" '.[$package]' "$policy")" >&2
  fi
done <<<"$targets")
[[ -n $targets ]] || exit 0
selected=$(jq -Rn '[inputs | select(length > 0)]' <<<"$targets")

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
if [[ $base_available == true ]]; then
  if ! base_derivations=$(derivation_map "git+file://$PWD?rev=$BASE_SHA#packages.$SYSTEM" "$selected"); then
    echo '::notice::Base derivation comparison unavailable; rebuilding selected packages.'
    base_derivations='{}'
  fi
fi

# Discover contracts without evaluating any unselected contract derivations.
contracts=$(nix eval --option allow-import-from-derivation false --json ".#applicationChecks.$SYSTEM" \
  --apply builtins.attrNames)
contract_suffixes=(cli gui wayland licenses appstream wayland-clipboard server quit-state host-tests-artifact appimage-runtime)
suffixes=$(printf '%s\n' "${contract_suffixes[@]}" | jq -Rn '[inputs]')
selected_contracts=$(jq -cn --argjson packages "$selected" --argjson contracts "$contracts" --argjson suffixes "$suffixes" '
  [$packages[] as $package | $suffixes[] | $package + "-" + .] | map(select(. as $name | $contracts | index($name)))')
application_checks=$(derivation_map ".#applicationChecks.$SYSTEM" "$selected_contracts")
jq -e --argjson selected "$selected_contracts" 'keys == ($selected | sort)' <<<"$application_checks" >/dev/null
base_application_checks='{}'
if [[ $base_available == true ]]; then
  if ! base_application_checks=$(derivation_map "git+file://$PWD?rev=$BASE_SHA#applicationChecks.$SYSTEM" "$selected_contracts"); then
    echo '::notice::Base application-check comparison unavailable; rebuilding selected contracts.'
    base_application_checks='{}'
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
      nix build ".#$package" --cores 0 --max-jobs 1 --keep-going --show-trace --print-build-logs
  fi
  # A test can change independently of its package. Compare its own full Nix
  # derivation, so changed contracts run without rebuilding identical contracts.
  for suffix in "${contract_suffixes[@]}"; do
    contract="$package-$suffix"
    if jq -e --arg contract "$contract" 'has($contract)' <<<"$application_checks" >/dev/null; then
      current_check=$(jq -er --arg contract "$contract" '.[$contract]' <<<"$application_checks")
      base_check=$(jq -r --arg contract "$contract" '.[$contract] // empty' <<<"$base_application_checks")
      if [[ -n $base_check && $base_check == "$current_check" ]]; then
        echo "$contract: unchanged check derivation; no rebuild needed."
        continue
      fi
      bash .github/scripts/build-with-fetch-retry.sh \
        nix build --no-link ".#applicationChecks.$SYSTEM.$contract" \
        --cores 0 --max-jobs 1 --keep-going --show-trace --print-build-logs
    fi
  done
  echo "::endgroup::"
done <<<"$targets"
