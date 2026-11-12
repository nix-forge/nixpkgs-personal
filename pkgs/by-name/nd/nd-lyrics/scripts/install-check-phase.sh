# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
unzip -t "$out/share/nd-lyrics.ndp" >/dev/null
unzip -p "$out/share/nd-lyrics.ndp" manifest.json | jq -e \
  --arg version "$version" '.name == "Lyrics" and .version == $version' >/dev/null
unzip -p "$out/share/nd-lyrics.ndp" plugin.wasm >"$TMPDIR/plugin.wasm"
od -An -tx1 -N4 "$TMPDIR/plugin.wasm" | grep -q '00 61 73 6d'
cmp LICENSE "$out/share/doc/nd-lyrics/LICENSE"
runHook postInstallCheck
