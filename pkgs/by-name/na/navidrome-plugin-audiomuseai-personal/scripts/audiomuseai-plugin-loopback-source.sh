# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp -R @upstreamSource@ "$out"
chmod -R u+w "$out"
required_hosts="$(jq -c '.permissions.http.requiredHosts' "$out/manifest.json")"
if [ "$required_hosts" = '["*"]' ]; then
  jq '.permissions.http.requiredHosts = ["127.0.0.1"]' \
    "$out/manifest.json" >"$out/manifest.json.tmp"
  mv "$out/manifest.json.tmp" "$out/manifest.json"
elif [ "$required_hosts" != '["127.0.0.1"]' ]; then
  printf 'Unexpected AudioMuse-AI HTTP requiredHosts: %s\n' "$required_hosts" >&2
  exit 1
fi
