# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
packed_required_hosts="$(
  unzip -p "$out/share/audiomuseai.ndp" manifest.json |
    jq -c '.permissions.http.requiredHosts'
)"
if [ "$packed_required_hosts" != '["127.0.0.1"]' ]; then
  printf 'Packed AudioMuse-AI HTTP requiredHosts are unsafe: %s\n' \
    "$packed_required_hosts" >&2
  exit 1
fi
install -Dm444 LICENSE "$out/share/doc/navidrome-plugin-audiomuseai-personal/LICENSE"
