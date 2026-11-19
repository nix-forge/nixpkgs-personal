{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "steam";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.appdmg;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;
  dontBuild = true;
  dontConfigure = true;

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        launcherSource = replaceVars ./scripts/steam-launcher.sh.in { runtimeOutput = null; };
        inherit pname;
      }
    }
  '';

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Valve's official Steam app bundle for macOS";
    homepage = "https://store.steampowered.com/about/";
    license = lib.licenses.unfree;
    mainProgram = "steam";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Steam.app"; };
}
