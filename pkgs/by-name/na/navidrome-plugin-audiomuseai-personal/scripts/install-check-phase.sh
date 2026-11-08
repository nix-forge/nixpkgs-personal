# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
unzip -t "$out/share/$pname.ndp" >/dev/null
unzip -p "$out/share/audiomuseai.ndp" manifest.json | jq -e \
  '.permissions.http.requiredHosts == ["127.0.0.1"]' >/dev/null
unzip -p "$out/share/audiomuseai.ndp" plugin.wasm >"$TMPDIR/plugin.wasm"
od -An -tx1 -N4 "$TMPDIR/plugin.wasm" | grep -q '00 61 73 6d'
test -s "$out/share/doc/navidrome-plugin-audiomuseai-personal/LICENSE"
runHook postInstallCheck
