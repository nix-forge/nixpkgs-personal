{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:

let
  pname = "linearmouse";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ _7zz ];
  strictDeps = true;

  # LinearMouse's DMG contains APFS rather than HFS, so undmg cannot unpack it.
  # Suppress NTFS/APFS alternate streams as 7-Zip would otherwise materialize a
  # quarantine stream as an Info.plist:com.apple.quarantine file and invalidate
  # the embedded LaunchAtLogin helper's signature.
  unpackPhase = ''
    runHook preUnpack

    7zz x -sns- "$src"

    runHook postUnpack
  '';

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # Any generic mutation of this bundle would invalidate its notarized
  # Developer ID signature and make its TCC identity less stable.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications"
    cp -a LinearMouse.app "$out/Applications/"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Customizable mouse and trackpad utility for macOS";
    homepage = "https://linearmouse.app/";
    downloadPage = "https://github.com/linearmouse/linearmouse/releases";
    changelog = "https://github.com/linearmouse/linearmouse/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
