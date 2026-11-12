# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
module="$out/share/powershell/Modules/PSScriptAnalyzer"
install -d "$module/PSv7" "$module/Settings" "$module/compatibility_profiles" \
  "$module/en-US" "$out/share/doc/psscriptanalyzer"
sed "s/{{ModuleVersion}}/$version/g" Engine/PSScriptAnalyzer.psd1 >"$module/PSScriptAnalyzer.psd1"
cp Engine/PSScriptAnalyzer.psm1 Engine/ScriptAnalyzer.format.ps1xml \
  Engine/ScriptAnalyzer.types.ps1xml "$module/"
cp Engine/Settings/* "$module/Settings/"
cp PSCompatibilityCollector/profiles/* "$module/compatibility_profiles/"
for assembly in \
  Microsoft.Windows.PowerShell.ScriptAnalyzer.dll \
  Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll \
  Microsoft.PowerShell.CrossCompatibility.dll \
  Pluralize.NET.dll; do
  case "$assembly" in
  Microsoft.Windows.PowerShell.ScriptAnalyzer.dll)
    build_dir=Engine/bin/PSV7Release/net8
    ;;
  Microsoft.PowerShell.CrossCompatibility.dll)
    build_dir=PSCompatibilityCollector/Microsoft.PowerShell.CrossCompatibility/bin/PSV7Release/netstandard2.0
    ;;
  *) build_dir=Rules/bin/PSV7Release/net8 ;;
  esac
  mapfile -t matches < <(find "$build_dir" -type f -name "$assembly")
  test "${#matches[@]}" -eq 1
  install -Dm444 "${matches[0]}" "$module/PSv7/$assembly"
done
unzip -p @helpArchive@ en-US/Microsoft.Windows.PowerShell.ScriptAnalyzer.dll-Help.xml \
  >"$module/en-US/Microsoft.Windows.PowerShell.ScriptAnalyzer.dll-Help.xml"
install -Dm444 LICENSE "$module/LICENSE"
install -Dm444 ThirdPartyNotices.txt "$module/ThirdPartyNotices.txt"
install -Dm444 LICENSE "$out/share/doc/psscriptanalyzer/LICENSE"
install -Dm444 ThirdPartyNotices.txt "$out/share/doc/psscriptanalyzer/ThirdPartyNotices.txt"
runHook postInstall
