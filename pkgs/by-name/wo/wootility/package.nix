{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

let
  pname = "wootility";
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

  installPhase = ''
    runHook preInstall

    test -x Wootility.app/Contents/MacOS/Wootility
    install -d "$out/Applications" "$out/bin"
    cp -a Wootility.app "$out/Applications/"
    ln -s "$out/Applications/Wootility.app/Contents/MacOS/Wootility" "$out/bin/wootility"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Customization and management software for Wooting keyboards";
    homepage = "https://wooting.io/wootility";
    downloadPage = "https://wooting.io/wootility";
    license = lib.licenses.unfree;
    mainProgram = "wootility";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
