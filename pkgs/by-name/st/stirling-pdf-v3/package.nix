{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  jdk25,
  makeWrapper,
  python3,
  nodejs_24,
  runCommand,
  curl,
}:
let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "stirling-pdf-v3";
  inherit (source) version;
  strictDeps = true;

  src = fetchurl {
    url = "https://github.com/Stirling-Tools/Stirling-PDF/releases/download/v${finalAttrs.version}/Stirling-PDF-with-login.jar";
    hash = source.jarHash;
  };
  scripts = fetchFromGitHub {
    owner = "Stirling-Tools";
    repo = "Stirling-PDF";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };
  python = python3.withPackages (packages: [ packages.fonttools ]);
  viewerPatchSources = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./scripts/check-viewer-font-fallback.mts
      ./extract_viewer.py
    ];
  };

  nativeBuildInputs = [
    makeWrapper
    python3
  ];
  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        java = lib.getExe jdk25;
        pythonPath = lib.makeBinPath [ finalAttrs.python ];
      }
    }
  '';

  passthru.tests.runtime = runCommand "stirling-pdf-v3-runtime" { nativeBuildInputs = [ curl ]; } ''
    source ${
      replaceVars ./scripts/stirling-pdf-v3-runtime.sh {
        mainExecutable = lib.getExe finalAttrs.finalPackage;
        inherit (finalAttrs) version;
        package = finalAttrs.finalPackage;
        fontHelperPython = lib.getExe finalAttrs.python;
      }
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nodejs_24 ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        extract_viewer_py = "${finalAttrs.viewerPatchSources}/extract_viewer.py";
        check_viewer_font_fallback_mts = "${finalAttrs.viewerPatchSources}/scripts/check-viewer-font-fallback.mts";
      }
    }
  '';

  meta = {
    description = "Stirling PDF 3 server with login and the complete web interface";
    homepage = "https://github.com/Stirling-Tools/Stirling-PDF";
    changelog = "https://github.com/Stirling-Tools/Stirling-PDF/releases/tag/v${finalAttrs.version}";
    # The login-enabled release bundles proprietary authentication and UI code.
    license = with lib.licenses; [
      mit
      unfree
    ];
    mainProgram = "Stirling-PDF";
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
  };
})
