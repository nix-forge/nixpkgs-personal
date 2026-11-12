# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs. The quoted program receives literal dollar expressions.
# shellcheck disable=SC2016,SC2154
runHook preInstallCheck
export HOME="$TMPDIR/home" DOTNET_CLI_HOME="$TMPDIR/dotnet" POWERSHELL_TELEMETRY_OPTOUT=1
mkdir -p "$HOME"
ANALYZER_PATH="$out/share/powershell/Modules/PSScriptAnalyzer/PSScriptAnalyzer.psd1" \
  pwsh -NoLogo -NoProfile -NonInteractive -File @analyzerSmoke@

test -s "$out/share/powershell/Modules/PSScriptAnalyzer/en-US/Microsoft.Windows.PowerShell.ScriptAnalyzer.dll-Help.xml"
cmp LICENSE "$out/share/powershell/Modules/PSScriptAnalyzer/LICENSE"
runHook postInstallCheck
