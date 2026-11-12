# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
for assembly in Moonfin.Server.dll SharpCompress.dll; do
  mapfile -t matches < <(find Jellyfin/backend/bin/Release/net8.0 \
    -type f -name "$assembly")
  test "${#matches[@]}" -eq 1
  install -Dm444 "${matches[0]}" "$out/$assembly"
done
install -Dm444 LICENSE "$out/share/doc/moonbase-server/LICENSE"
runHook postInstall
