# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm444 @server@/Moonfin.Server.dll "$out/Moonfin.Server.dll"
install -Dm444 @server@/SharpCompress.dll "$out/SharpCompress.dll"
mkdir -p "$out/frontend"
cp -R @web@/. "$out/frontend/"
chmod -R u+w "$out/frontend/theme"
rm -rf "$out/frontend/theme"
cp -R @pluginSource@/Jellyfin/frontend/theme "$out/frontend/theme"
install -Dm444 @pluginSource@/LICENSE \
  "$out/share/doc/jellyfin-plugin-moonbase/LICENSE"
install -Dm444 @web_src@/LICENSE \
  "$out/share/doc/jellyfin-plugin-moonbase/MOONFIN-CORE-LICENSE"
jq --arg version "$version" --arg tag @releaseTag@ '
  .[0] as $plugin |
  ($plugin.versions | map(select(.version == $version)) |
    if length == 1 then .[0] else error("expected one Moonbase release") end) as $release |
  if ($release.sourceUrl | contains("/releases/download/" + $tag + "/")) then
  {
    category: $plugin.category,
    changelog: $release.changelog,
    description: $plugin.description,
    guid: $plugin.guid,
    name: $plugin.name,
    overview: $plugin.overview,
    owner: $plugin.owner,
    targetAbi: $release.targetAbi,
    timestamp: ($release.timestamp + "Z"),
    version: $release.version,
    status: "Active",
    autoUpdate: false,
    assemblies: ["Moonfin.Server.dll"]
  }
  else error("Moonbase manifest release tag mismatch") end
' @manifestSource@ >"$out/meta.json"
runHook postInstall
