{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  powershell,
}:
let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "psscriptanalyzer";
  inherit (source) version;
  src = fetchurl {
    url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${source.version}";
    inherit (source) hash;
  };
  strictDeps = true;
  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/powershell/Modules/PSScriptAnalyzer" "$out/share/doc/psscriptanalyzer"
    unzip -q "$src" -d "$out/share/powershell/Modules/PSScriptAnalyzer"
    cp "$out/share/powershell/Modules/PSScriptAnalyzer/LICENSE" "$out/share/doc/psscriptanalyzer/"
    runHook postInstall
  '';
  doInstallCheck = true;
  nativeInstallCheckInputs = [ powershell ];
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home" DOTNET_CLI_HOME="$TMPDIR/dotnet" POWERSHELL_TELEMETRY_OPTOUT=1
    mkdir -p "$HOME"
    ANALYZER_PATH="$out/share/powershell/Modules/PSScriptAnalyzer/PSScriptAnalyzer.psd1" \
      pwsh -NoLogo -NoProfile -NonInteractive -Command '
        $ErrorActionPreference = "Stop"
        Import-Module $env:ANALYZER_PATH
        $findings = @(Invoke-ScriptAnalyzer -ScriptDefinition "`$unused = 1")
        if ($findings.RuleName -notcontains "PSUseDeclaredVarsMoreThanAssignments") {
          throw "Analyzer failed to detect an unused variable"
        }
      '
    runHook postInstallCheck
  '';
  passthru.modulePath = "${finalAttrs.finalPackage}/share/powershell/Modules/PSScriptAnalyzer";
  meta = {
    description = "Static analysis rules for PowerShell scripts and modules";
    homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    inherit (powershell.meta) platforms;
  };
})
