{
  callPackage,
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

let
  pname = "wootility-bin";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  strictDeps = true;

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # Generic fixup would invalidate Wooting's notarized Developer ID signature.
  dontFixup = true;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Customization and management software for Wooting keyboards";
    homepage = "https://wooting.io/wootility";
    downloadPage = "https://wooting.io/wootility";
    license = lib.licenses.unfree;
    mainProgram = "wootility";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Wootility.app"; };
}
