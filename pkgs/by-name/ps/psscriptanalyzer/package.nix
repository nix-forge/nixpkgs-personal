{
  callPackage,
  replaceVars,
  lib,
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
  fetchurl,
  powershell,
  unzip,
}:
let
  source = import ./source.nix;
  helpArchive = fetchurl {
    url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${source.version}";
    hash = source.helpHash;
  };
in
buildDotnetModule (finalAttrs: {
  pname = "psscriptanalyzer";
  inherit (source) version;
  src = fetchFromGitHub {
    owner = "PowerShell";
    repo = "PSScriptAnalyzer";
    rev = source.sourceRev;
    inherit (source) hash;
  };
  projectFile = "Rules/Rules.csproj";
  nugetDeps = ./deps.json;
  buildType = "PSV7Release";
  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;
  # Select the module's PowerShell 7 target only for the build. Its project
  # references a netstandard2.0 library, which must restore for that target.
  dotnetBuildFlags = [
    "--framework"
    "net8"
  ];
  executables = [ ];
  strictDeps = true;
  nativeBuildInputs = [ unzip ];
  postPatch = builtins.readFile ./scripts/post-patch.sh;
  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit helpArchive;
      }
    }
  '';
  doInstallCheck = true;
  nativeInstallCheckInputs = [ powershell ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        analyzerSmoke = "${./scripts/analyzer-smoke.ps1}";
      }
    }
  '';
  passthru.modulePath = "${finalAttrs.finalPackage}/share/powershell/Modules/PSScriptAnalyzer";
  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  meta = {
    description = "Static analysis rules for PowerShell scripts and modules";
    homepage = "https://github.com/PowerShell/PSScriptAnalyzer";
    license = lib.licenses.mit;
    # Pluralize.NET is a pinned NuGet assembly included in the module.
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    inherit (powershell.meta) platforms;
  };
})
