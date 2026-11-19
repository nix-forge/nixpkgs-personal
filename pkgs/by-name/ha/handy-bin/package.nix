{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  pname = "handy-bin";
  inherit (source) version;
  src = fetchurl { inherit (source) url hash; };
  strictDeps = true;
  sourceRoot = ".";
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # The complete upstream bundle retains its Developer ID signature and ticket.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Handy.app "$out/Applications/Handy.app"
    ln -s "$out/Applications/Handy.app/Contents/MacOS/handy" "$out/bin/handy"
    runHook postInstall
  '';
  meta = {
    description = "Offline speech-to-text application with the upstream macOS signature preserved";
    homepage = "https://github.com/cjpais/Handy";
    changelog = "https://github.com/cjpais/Handy/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "handy";
  }
  // lib.optionalAttrs (lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11") {
    mainDarwinApp = "Handy.app";
  };
}
