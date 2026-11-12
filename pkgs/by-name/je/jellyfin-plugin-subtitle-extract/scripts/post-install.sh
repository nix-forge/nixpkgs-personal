# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
install -Dm444 \
  "$out/lib/@pname@/Jellyfin.Plugin.SubtitleExtract.dll" \
  "$out/Jellyfin.Plugin.SubtitleExtract.dll"
# The Jellyfin service copies this output into its plugin directory. Keep
# only the plugin DLL, not copies of Jellyfin's own NuGet assemblies.
rm -r "${out:?}/lib"
yq -o=json '.' build.yaml | jq \
  --arg version "$version" \
  --arg timestamp @releaseTimestamp@ \
  'del(.framework, .artifacts) | .version = $version | .guid |= ascii_downcase | .timestamp = $timestamp | .autoUpdate = false' \
  >"$out/meta.json"
install -Dm444 LICENSE "$out/share/doc/@pname@/LICENSE"
