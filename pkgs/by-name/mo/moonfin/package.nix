{
  callPackage,
  fetchurl,
  lib,
  stdenv,
}:
let
  source = import ./source.nix;
  meta = {
    description = "Jellyfin and Emby client with Seerr discovery and requests";
    homepage = "https://github.com/Moonfin-Client/Moonfin-Core";
    changelog = "https://github.com/Moonfin-Client/Moonfin-Core/releases/tag/${source.releaseTag}";
    # The source tree also bundles OFL fonts and the MIT/BSD archive runtime.
    license = [
      lib.licenses.gpl2Plus
      lib.licenses.ofl
      lib.licenses.mit
      lib.licenses.bsd3
    ];
    mainProgram = "moonfin";
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance =
      if stdenv.hostPlatform.isDarwin then
        [ lib.sourceTypes.binaryNativeCode ]
      else
        with lib.sourceTypes;
        [
          fromSource
          binaryNativeCode
          binaryBytecode
        ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Moonfin.app"; };
in
if stdenv.hostPlatform.isDarwin then
  callPackage ./darwin.nix {
    pname = "moonfin";
    inherit (source) version;
    src = fetchurl source.sources.aarch64-darwin;
    inherit meta;
  }
else
  callPackage ./linux.nix { inherit meta; }
